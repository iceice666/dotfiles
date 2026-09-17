import { describe, expect, test } from "bun:test";
import { applyAction, emptyState, formatTodos, parseState, type Action, type State } from "../model";

const add = (state: State, text = "任務", extra: Partial<Action> = {}) => applyAction(state, { action: "add", text, ...extra });
const update = (state: State, id: number, fields: Partial<Action>) => applyAction(state, { action: "update", id, ...fields });

function chain(): State {
	return add(add(emptyState(), "前置任務"), "後續任務", { blockedBy: [1] });
}

function rawTodo(id = 1) {
	return { id, text: "任務", status: "pending", blockedBy: [] };
}

function invalidAction(action: unknown): Action {
	return action as Action;
}

describe("immutable task transactions", () => {
	test("fresh empty state, defaults, trimming, monotonic IDs", () => {
		const initial = emptyState();
		const first = add(initial, "  編寫測試  ", { activeForm: " 正在測試 " });
		expect(first.todos).toEqual([{ id: 1, text: "編寫測試", status: "pending", activeForm: "正在測試", blockedBy: [] }]);
		expect(initial).toEqual(emptyState());
		const cleared = applyAction(first, { action: "clear" });
		expect(cleared.nextId).toBe(2);
		expect(add(cleared).todos[0].id).toBe(2);
		expect(emptyState()).not.toBe(emptyState());
	});

	test("copies lists, action dependencies, and updates without input mutation", () => {
		const base = add(emptyState());
		const deps = [1];
		const state = add(base, "第二項", { blockedBy: deps });
		deps.length = 0;
		expect(state.todos[1].blockedBy).toEqual([1]);
		const listed = applyAction(state, { action: "list" });
		listed.todos[1].blockedBy.length = 0;
		expect(state.todos[1].blockedBy).toEqual([1]);
		const revised = update(state, 2, { text: " 新標題 ", activeForm: " 更新中 ", blockedBy: [] });
		expect(revised.todos[1]).toEqual({ id: 2, text: "新標題", activeForm: "更新中", blockedBy: [], status: "pending" });
		expect(state.todos[1].text).toBe("第二項");
	});

	test("dependency completion gates progress and rejects reopening atomically", () => {
		const state = chain();
		for (const status of ["in_progress", "completed"] as const) {
			expect(() => update(state, 2, { status })).toThrow();
		}
		const unlocked = update(state, 1, { status: "completed" });
		const active = update(unlocked, 2, { status: "in_progress" });
		const snapshot = JSON.stringify(active);
		expect(() => update(active, 1, { status: "pending", text: "不能洩漏" })).toThrow();
		expect(JSON.stringify(active)).toBe(snapshot);
		const complete = update(active, 2, { status: "completed" });
		expect(() => update(complete, 1, { status: "in_progress" })).toThrow();
		expect(update(update(complete, 2, { status: "pending" }), 1, { status: "pending" }).todos[0].status).toBe("pending");
	});

	test("rejects missing, self, repeated, and cyclic dependencies", () => {
		const state = chain();
		for (const blockedBy of [[3], [1], [2, 2], [0], [-1], [1.2]]) {
			expect(() => update(state, 1, { blockedBy })).toThrow();
		}
		expect(() => update(state, 1, { blockedBy: [2] })).toThrow();
		const three = add(state, "第三項", { blockedBy: [2] });
		expect(() => update(three, 1, { blockedBy: [3] })).toThrow();
		expect(() => add(emptyState(), "自己", { blockedBy: [1] })).toThrow();
		expect(() => add(state, "未解锁", { blockedBy: [2], status: "completed" })).toThrow();
	});

	test("remove protects dependents; prune drops completed tasks and edges", () => {
		const state = update(chain(), 1, { status: "completed" });
		expect(() => applyAction(state, { action: "remove", id: 1 })).toThrow();
		const pruned = applyAction(state, { action: "prune" });
		expect(pruned.todos).toEqual([{ id: 2, text: "後續任務", status: "pending", blockedBy: [] }]);
		expect(pruned.nextId).toBe(3);
		expect(state.todos[1].blockedBy).toEqual([1]);
		expect(applyAction(pruned, { action: "remove", id: 2 }).todos).toEqual([]);
		expect(applyAction(emptyState(), { action: "prune" })).toEqual(emptyState());
	});

	test("validates action shape, IDs, and runtime field types", () => {
		const state = add(emptyState());
		for (const action of [null, {}, { action: "wat" }, { action: "update" }, { action: "remove", id: 2 }, { action: "update", id: "1" }, { action: "add", text: 42 }, { action: "update", id: 1, status: "done" }, { action: "update", id: 1, blockedBy: null }]) {
			expect(() => applyAction(state, invalidAction(action))).toThrow();
		}
	});

	test("enforces text, control-character, task, and dependency bounds", () => {
		for (const text of ["", "   ", "x".repeat(201), "a\nb", "a\tb", "a\0b", "a\u007fb", "a\u0085b", "a\u2028b"]) {
			expect(() => add(emptyState(), text)).toThrow();
		}
		for (const activeForm of ["", " ", "x".repeat(101), "hello\rworld"]) {
			expect(() => add(emptyState(), "任務", { activeForm })).toThrow();
		}
		expect(add(emptyState(), "中".repeat(200), { activeForm: "進".repeat(100) }).todos).toHaveLength(1);
		let state = emptyState();
		for (let i = 0; i < 50; i++) state = add(state);
		expect(() => add(state)).toThrow();
		expect(() => update(state, 1, { blockedBy: Array.from({ length: 51 }, (_, i) => i + 1) })).toThrow();
		const exhausted: State = { version: 1, nextId: 1_000_000, todos: [] };
		expect(() => add(exhausted)).toThrow();
		expect(exhausted.todos).toEqual([]);
	});
});

describe("task categories", () => {
	test("adds trimmed categories, preserves omitted categories, updates and clears them", () => {
		const original = add(emptyState(), "任務", { category: "  開發  " });
		expect(original.todos[0].category).toBe("開發");
		const revised = update(original, 1, { text: "更新" });
		expect(revised.todos[0].category).toBe("開發");
		expect(update(revised, 1, { category: "  測試  " }).todos[0].category).toBe("測試");
		for (const category of ["", "   ", "\u3000"]) {
			expect(update(revised, 1, { category }).todos[0]).not.toHaveProperty("category");
			expect(add(emptyState(), "任務", { category }).todos[0]).not.toHaveProperty("category");
		}
		expect(original.todos[0].category).toBe("開發");
		expect(add(emptyState(), "任務", { category: ` ${"中".repeat(60)} ` }).todos[0].category).toBe("中".repeat(60));
	});

	test("invalid categories fail add and update atomically", () => {
		const base = add(emptyState(), "任務", { category: "原分類" });
		const snapshot = structuredClone(base);
		for (const category of [null, 42, false, [], {}, "x".repeat(61), "a\nb", "\t", "\0", "\u007f", "\u0085", "\u2028", "\u2029"]) {
			expect(() => applyAction(base, invalidAction({ action: "add", text: "新任務", category }))).toThrow(/category/);
			expect(() => applyAction(base, invalidAction({ action: "update", id: 1, text: "不能洩漏", category }))).toThrow(/category/);
			expect(base).toEqual(snapshot);
		}
		const blocked = add(base, "後續", { blockedBy: [1], category: "保留" });
		expect(() => update(blocked, 2, { category: "変更", status: "completed" })).toThrow();
		expect(blocked.todos[1].category).toBe("保留");
	});

	test("batch categories normalize independently and invalid later entries roll back", () => {
		const base = add(emptyState(), "現有", { category: "現有分類" });
		const result = applyAction(base, { action: "add", items: [
			{ text: "準備", category: " 開發 ", status: "completed" },
			{ text: "執行", category: "測試", blockedBy: [2] },
			{ text: "未分類", category: " " },
			{ text: "省略分類" },
		] });
		expect(result.todos.map(todo => todo.category)).toEqual(["現有分類", "開發", "測試", undefined, undefined]);
		expect(result.todos[3]).not.toHaveProperty("category");
		const snapshot = structuredClone(base);
		for (const category of [null, "x".repeat(61), "a\nb"]) {
			expect(() => applyAction(base, invalidAction({ action: "add", items: [
				{ text: "有效", category: "有效分類" }, { text: "無效", category },
			] }))).toThrow();
			expect(base).toEqual(snapshot);
		}
		for (const category of ["混合", "", " ", null]) {
			expect(() => applyAction(base, invalidAction({ action: "add", category, items: [{ text: "新任務" }] }))).toThrow(/single-task fields/);
		}
	});

	test("categorized persistence remains version 1 and rejects invalid persisted categories", () => {
		const old = { version: 1, nextId: 2, todos: [rawTodo()] };
		expect(parseState(old)).toEqual(old);
		const state = add(emptyState(), "任務", { category: "分類" });
		expect(parseState(JSON.parse(JSON.stringify(state)))).toEqual(state);
		const source = { ...old, todos: [{ ...rawTodo(), category: " 分類 " }] };
		const parsed = parseState(source)!;
		expect(parsed.todos[0].category).toBe("分類");
		parsed.todos[0].category = "獨立副本";
		expect(source.todos[0].category).toBe(" 分類 ");
		for (const category of ["", " ", null, 42, false, {}, [], "x".repeat(61), "a\nb", "\u2029"]) {
			expect(parseState({ version: 1, nextId: 3, todos: [rawTodo(), { ...rawTodo(2), category }] })).toBeUndefined();
		}
	});

	test("plain output includes categories without altering uncategorized lines or ordering", () => {
		const first = add(emptyState(), "準備", { category: "開發", status: "completed" });
		const second = add(first, "執行", { category: "測試", blockedBy: [1] });
		const state = add(second, "檢查");
		expect(formatTodos(state)).toBe("#1 [Completed] [Category: 開發] 準備\n#2 [Pending] [Category: 測試] 執行; depends on: #1\n#3 [Pending] 檢查");
	});
});

describe("batch add transactions", () => {
	test("assigns ordered IDs, normalizes fields and supports earlier dependencies", () => {
		const base = add(emptyState());
		const items = [
			{ text: " 準備 ", status: "completed" as const },
			{ text: " 執行 ", status: "in_progress" as const, activeForm: " 執行中 ", blockedBy: [2] },
			{ text: "驗證", blockedBy: [3] },
		];
		const result = applyAction(base, { action: "add", items });
		expect(result.nextId).toBe(5);
		expect(result.todos.slice(1)).toEqual([
			{ id: 2, text: "準備", status: "completed", blockedBy: [] },
			{ id: 3, text: "執行", status: "in_progress", activeForm: "執行中", blockedBy: [2] },
			{ id: 4, text: "驗證", status: "pending", blockedBy: [3] },
		]);
		items[1].blockedBy!.length = 0;
		expect(result.todos[2].blockedBy).toEqual([2]);
		expect(base.todos).toHaveLength(1);
	});

	test("rejects malformed batches and mixed fields without modifying state", () => {
		const base = add(emptyState());
		const before = structuredClone(base);
		const badItems = [null, {}, [], [null], ["task"], [{}], [{ text: "ok" }, { text: " " }],
			[{ text: "x", items: [] }], [{ text: "x", action: "clear" }],
			[{ text: "x", blockedBy: [2] }], [{ text: "x", blockedBy: [3] }, { text: "y" }],
			[{ text: "x", status: "completed", blockedBy: [1] }],
			[{ text: "x", activeForm: "a".repeat(101) }]];
		for (const items of badItems) {
			expect(() => applyAction(base, invalidAction({ action: "add", items }))).toThrow();
			expect(base).toEqual(before);
		}
		for (const fields of [{ text: "x" }, { id: 1 }, { status: "pending" }, { activeForm: "x" }, { blockedBy: [] }]) {
			expect(() => applyAction(base, invalidAction({ action: "add", items: [{ text: "x" }], ...fields }))).toThrow();
		}
		for (const action of ["list", "update", "remove", "prune", "clear"]) {
			expect(() => applyAction(base, invalidAction({ action, id: 1, items: [{ text: "x" }] }))).toThrow();
		}
	});

	test("enforces total capacity and ID exhaustion atomically", () => {
		const items = Array.from({ length: 50 }, () => ({ text: "任務" }));
		expect(applyAction(emptyState(), { action: "add", items }).todos).toHaveLength(50);
		expect(() => applyAction(emptyState(), { action: "add", items: [...items, { text: "超額" }] })).toThrow();
		const base = add(emptyState());
		expect(() => applyAction(base, { action: "add", items })).toThrow();
		expect(base.nextId).toBe(2);
		const last: State = { version: 1, nextId: 999999, todos: [] };
		expect(() => applyAction(last, { action: "add", items: items.slice(0, 2) })).toThrow();
		expect(last.todos).toEqual([]);
		expect(applyAction(last, { action: "add", items: items.slice(0, 1) }).nextId).toBe(1000000);
	});
});

describe("persisted state", () => {
	test("round trips and owns its normalized copy", () => {
		const state = chain();
		expect(parseState(JSON.parse(JSON.stringify(state)))).toEqual(state);
		const parsed = parseState(state)!;
		parsed.todos[1].blockedBy.push(99);
		expect(state.todos[1].blockedBy).toEqual([1]);
		expect(parseState({ version: 1, nextId: 2, todos: [{ ...rawTodo(), text: " 標題 " }] })?.todos[0].text).toBe("標題");
	});

	test("rejects malformed state rather than partly salvaging it", () => {
		const bad: unknown[] = [
			null, [], "{}", {}, { version: 2, nextId: 1, todos: [] },
			...[0, -1, 1.5, Infinity, 1_000_001, Number.MAX_SAFE_INTEGER + 1, "2"].map((nextId) => ({ version: 1, nextId, todos: [] })),
			{ version: 1, nextId: 2, todos: null },
			{ version: 1, nextId: 1, todos: [rawTodo()] },
			{ version: 1, nextId: 3, todos: [rawTodo(), rawTodo()] },
			{ version: 1, nextId: 2, todos: [null] },
			{ version: 1, nextId: 2, todos: [{ ...rawTodo(), blockedBy: [9] }] },
			{ version: 1, nextId: 2, todos: [{ ...rawTodo(), blockedBy: [1] }] },
			{ version: 1, nextId: 2, todos: [{ ...rawTodo(), text: "" }] },
			{ version: 1, nextId: 2, todos: [{ ...rawTodo(), status: "other" }] },
			{ version: 1, nextId: 2, todos: [{ ...rawTodo(), activeForm: 8 }] },
			{ version: 1, nextId: 3, todos: [{ ...rawTodo(), blockedBy: [2] }, { ...rawTodo(2), blockedBy: [1] }] },
			{ version: 1, nextId: 3, todos: [rawTodo(), { ...rawTodo(2), blockedBy: [1], status: "completed" }] },
			{ version: 1, nextId: 52, todos: Array.from({ length: 51 }, (_, i) => rawTodo(i + 1)) },
		];
		for (const value of bad) expect(parseState(value)).toBeUndefined();
	});
});

describe("plain Chinese output", () => {
	test("shows all tasks, IDs, states, and dependencies but not active forms", () => {
		expect(formatTodos(emptyState())).toBe("No tasks yet.");
		const first = add(emptyState(), "準備", { status: "completed" });
		const second = add(first, "執行", { status: "in_progress", blockedBy: [1], activeForm: "正在執行" });
		const state = add(second, "檢查", { blockedBy: [2] });
		expect(formatTodos(state)).toBe("#1 [Completed] 準備\n#2 [In progress] 執行; depends on: #1\n#3 [Pending] 檢查; depends on: #2");
	});

	test("does not truncate valid large task lists", () => {
		let state = emptyState();
		for (let i = 0; i < 50; i++) state = add(state, "中".repeat(200));
		const output = formatTodos(state);
		expect(output.split("\n")).toHaveLength(50);
		expect(output).toContain("#50 [Pending]");
		expect(Buffer.byteLength(output)).toBeLessThan(50_000);
		const dense: State = {
			version: 1,
			nextId: 1_000_000,
			todos: Array.from({ length: 50 }, (_, i) => ({
				id: 999_950 + i,
				text: "中".repeat(200),
				status: "pending",
				activeForm: "進".repeat(100),
				blockedBy: Array.from({ length: i }, (_, j) => 999_950 + j),
			})),
		};
		expect(Buffer.byteLength(formatTodos(dense))).toBeLessThan(50_000);
	});
});
