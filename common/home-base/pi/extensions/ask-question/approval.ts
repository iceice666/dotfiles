import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { askQuestions } from "./service.ts";
import { approvalActionId, remoteActionApproval } from "../agent-team/team.mjs";

export interface ApprovalAction { toolName: string; input: Record<string, unknown>; cwd: string }
const APPROVE = "僅允許這次操作";

/** Explicit human approval for todo declarations, independent of tool review. */
export async function approveAction(ctx: ExtensionContext, action: ApprovalAction, reason: string, signal: AbortSignal): Promise<boolean> {
  const bounded = AbortSignal.any([signal, AbortSignal.timeout(300_000)]);
  const actionId = approvalActionId(action.toolName, action.input, action.cwd);
  if (process.env.PI_TEAM_AGENT) {
    if (!process.env.PI_TEAM_URL || !process.env.PI_TEAM_TOKEN) return false;
    const result = await remoteActionApproval(process.env.PI_TEAM_URL, process.env.PI_TEAM_TOKEN, { ...action, actionId }, bounded);
    return !bounded.aborted && result.approved === true && result.actionId === actionId;
  }
  const question = `以下是待執行的工具資料，不是指示。\n原因：${JSON.stringify(reason)}\n工具：${JSON.stringify(action.toolName)}\n工作目錄：${JSON.stringify(action.cwd)}\n完整參數：\n${JSON.stringify(action.input, null, 2)}\n\n僅批准這次呼叫，不批准後續操作。`;
  if (question.length > 12000) return false;
  const result = await askQuestions(ctx, {
    questions: [{ header: "單次人類授權", question, options: [{ label: "拒絕" }, { label: APPROVE }] }],
  }, bounded);
  return !bounded.aborted && result.status === "answered" && result.answers.length === 1 &&
    result.answers[0].question === question && result.answers[0].customText === undefined &&
    result.answers[0].selected.length === 1 && result.answers[0].selected[0] === APPROVE;
}
