export type Status = "pending" | "in_progress" | "completed";

export interface Todo {
	id: number;
	text: string;
	status: Status;
	activeForm?: string;
	category?: string;
	blockedBy: number[];
}

export interface State {
	version: 1;
	nextId: number;
	todos: Todo[];
}

export interface AddItem {
	text: string;
	status?: Status;
	activeForm?: string;
	category?: string;
	blockedBy?: number[];
}

export interface Action {
	action: "list" | "add" | "update" | "remove" | "clear" | "prune";
	id?: number;
	items?: AddItem[];
	text?: string;
	status?: Status;
	activeForm?: string;
	category?: string;
	blockedBy?: number[];
}

const MAX_TODOS = 50;
const controls = /[\u0000-\u001f\u007f-\u009f\u2028\u2029]/;

function record(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

function positiveId(value: unknown): value is number {
	return typeof value === "number" && Number.isSafeInteger(value) && value > 0 && value <= 1_000_000;
}

function boundedText(value: unknown, name: string, limit: number): string {
	if (typeof value !== "string" || controls.test(value)) {
		throw new Error(`${name} must be a string without control characters`);
	}
	const result = value.trim();
	if (!result || result.length > limit) {
		throw new Error(`${name} must contain 1–${limit} characters`);
	}
	return result;
}

function actionCategory(value: unknown): string | undefined {
	if (typeof value === "string" && !controls.test(value) && !value.trim()) return undefined;
	return boundedText(value, "category", 60);
}

function validStatus(value: unknown): Status {
	if (value !== "pending" && value !== "in_progress" && value !== "completed") {
		throw new Error("Invalid task status");
	}
	return value;
}

function dependencies(value: unknown): number[] {
	if (!Array.isArray(value) || value.length > MAX_TODOS) {
		throw new Error("blockedBy must be an array of at most 50 task IDs");
	}
	const result: number[] = [];
	for (const id of value) {
		if (!positiveId(id) || result.includes(id)) {
			throw new Error("Dependency IDs must be unique positive integers");
		}
		result.push(id);
	}
	return result;
}

/** Validate and copy every field; callers never retain mutable input references. */
function checkedState(value: unknown): State {
	if (!record(value) || value.version !== 1 || !positiveId(value.nextId)) {
		throw new Error("Invalid task state version or nextId");
	}
	if (!Array.isArray(value.todos) || value.todos.length > MAX_TODOS) {
		throw new Error("Task count cannot exceed 50");
	}
	const todos: Todo[] = [];
	const byId = new Map<number, Todo>();
	for (const item of value.todos) {
		if (!record(item) || !positiveId(item.id) || byId.has(item.id) || item.id >= value.nextId) {
			throw new Error("Task ID is invalid, duplicated, or not less than nextId");
		}
		const todo: Todo = {
			id: item.id,
			text: boundedText(item.text, "text", 200),
			status: validStatus(item.status),
			blockedBy: dependencies(item.blockedBy),
		};
		if (item.activeForm !== undefined) todo.activeForm = boundedText(item.activeForm, "activeForm", 100);
		if (item.category !== undefined) todo.category = boundedText(item.category, "category", 60);
		todos.push(todo);
		byId.set(todo.id, todo);
	}
	for (const todo of todos) {
		for (const id of todo.blockedBy) {
			const dependency = byId.get(id);
			if (!dependency || id === todo.id) throw new Error("Dependencies cannot reference missing tasks or the task itself");
			if (todo.status !== "pending" && dependency.status !== "completed") {
				throw new Error(`Dependency #${id} of task #${todo.id} is not yet completed`);
			}
		}
	}
	const visiting = new Set<number>();
	const visited = new Set<number>();
	function visit(id: number): void {
		if (visiting.has(id)) throw new Error("Task dependencies cannot form cycles");
		if (visited.has(id)) return;
		visiting.add(id);
		for (const dependency of byId.get(id)!.blockedBy) visit(dependency);
		visiting.delete(id);
		visited.add(id);
	}
	for (const todo of todos) visit(todo.id);
	return { version: 1, nextId: value.nextId, todos };
}

export function emptyState(): State {
	return { version: 1, nextId: 1, todos: [] };
}

/** Corrupt or incompatible persisted data is never partially restored. */
export function parseState(value: unknown): State | undefined {
	try {
		return checkedState(value);
	} catch {
		return undefined;
	}
}

/** Every action is an atomic transaction, including reverse dependency checks. */
export function applyAction(state: State, action: Action): State {
	const next = checkedState(state);
	if (!record(action)) throw new Error("Invalid task action");
	if (action.items !== undefined) {
		if (action.action !== "add") throw new Error("items is only supported for add");
		if ([action.id, action.text, action.status, action.activeForm, action.category, action.blockedBy].some(value => value !== undefined)) {
			throw new Error("items cannot be combined with single-task fields");
		}
		if (!Array.isArray(action.items) || !action.items.length || action.items.length > MAX_TODOS) {
			throw new Error("items must be an array of 1–50 tasks");
		}
		if (next.todos.length + action.items.length > MAX_TODOS) throw new Error("Task count cannot exceed 50");
		if (next.nextId + action.items.length > 1_000_000) throw new Error("Task IDs exhausted");
		let batch = next;
		for (const item of action.items) {
			if (!record(item) || Object.keys(item).some(key => !["text", "status", "activeForm", "category", "blockedBy"].includes(key))) {
				throw new Error("Each entry in items must be a task object containing only text, status, activeForm, category, and blockedBy");
			}
			batch = applyAction(batch, { action: "add", text: item.text, status: item.status, activeForm: item.activeForm, category: item.category, blockedBy: item.blockedBy });
		}
		return batch;
	}
	switch (action.action) {
		case "list":
			return next;
		case "add": {
			if (next.todos.length >= MAX_TODOS) throw new Error("Task count cannot exceed 50");
			if (next.nextId === 1_000_000) throw new Error("Task IDs exhausted");
			const todo: Todo = {
				id: next.nextId++,
				text: boundedText(action.text, "text", 200),
				status: action.status === undefined ? "pending" : validStatus(action.status),
				blockedBy: action.blockedBy === undefined ? [] : dependencies(action.blockedBy),
			};
			if (action.activeForm !== undefined) todo.activeForm = boundedText(action.activeForm, "activeForm", 100);
			if (action.category !== undefined) {
				const category = actionCategory(action.category);
				if (category !== undefined) todo.category = category;
			}
			next.todos.push(todo);
			break;
		}
		case "update": {
			const todo = next.todos.find((item) => item.id === action.id);
			if (!positiveId(action.id) || !todo) throw new Error("Task ID not found");
			if (action.text !== undefined) todo.text = boundedText(action.text, "text", 200);
			if (action.status !== undefined) todo.status = validStatus(action.status);
			if (action.activeForm !== undefined) todo.activeForm = boundedText(action.activeForm, "activeForm", 100);
			if (action.blockedBy !== undefined) todo.blockedBy = dependencies(action.blockedBy);
			if (action.category !== undefined) {
				const category = actionCategory(action.category);
				if (category === undefined) delete todo.category;
				else todo.category = category;
			}
			break;
		}
		case "remove": {
			if (!positiveId(action.id) || !next.todos.some((todo) => todo.id === action.id)) {
				throw new Error("Task ID not found");
			}
			if (next.todos.some((todo) => todo.blockedBy.includes(action.id!))) {
				throw new Error("Cannot delete a task that other tasks still depend on");
			}
			next.todos = next.todos.filter((todo) => todo.id !== action.id);
			break;
		}
		case "clear":
			next.todos = [];
			break;
		case "prune": {
			const removed = new Set(next.todos.filter((todo) => todo.status === "completed").map((todo) => todo.id));
			next.todos = next.todos.filter((todo) => !removed.has(todo.id));
			for (const todo of next.todos) todo.blockedBy = todo.blockedBy.filter((id) => !removed.has(id));
			break;
		}
		default:
			throw new Error("Unknown task action");
	}
	return checkedState(next);
}

export function formatTodos(state: State, options: { unfinishedOnly?: boolean } = {}): string {
	// Validate the full graph before filtering display rows: completed dependencies still exist.
	const current = checkedState(state);
	const todos = options.unfinishedOnly ? current.todos.filter(todo => todo.status !== "completed") : current.todos;
	if (!todos.length) return "No tasks yet.";
	const labels: Record<Status, string> = { pending: "Pending", in_progress: "In progress", completed: "Completed" };
	return todos.map((todo) => {
		const blocked = todo.blockedBy.length ? `; depends on: ${todo.blockedBy.map((id) => `#${id}`).join(", ")}` : "";
		const category = todo.category === undefined ? "" : ` [Category: ${todo.category}]`;
		return `#${todo.id} [${labels[todo.status]}]${category} ${todo.text}${blocked}`;
	}).join("\n");
}
