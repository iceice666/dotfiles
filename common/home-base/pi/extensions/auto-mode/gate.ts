import { actionForTool, evaluatePolicy, type Action, type PolicyDecision } from "./policy.ts";

export interface Verdict { decision: "allow" | "ask" | "deny"; reason: string }
export interface GateServices {
  classify(action: Action, signal: AbortSignal): Promise<Verdict>;
  approve(action: Action, reason: string, signal: AbortSignal): Promise<boolean>;
  policy?: (action: Action) => PolicyDecision;
}
export type GateResult = undefined | { block: true; reason: string };

/** Every approval is consumed by this call; nothing is cached across executions. */
export async function guardTool(
  toolName: string, input: Record<string, unknown>, cwd: string,
  services: GateServices, signal: AbortSignal,
): Promise<GateResult> {
  const blocked = (reason: string): GateResult => ({ block: true, reason: `Auto Mode: ${reason} Do not retry equivalent actions through another tool or agent to evade review.` });
  try {
    signal.throwIfAborted();
    const original = JSON.stringify(input);
    const action = actionForTool(toolName, input, cwd);
    const policy = (services.policy ?? evaluatePolicy)(action);
    let allowed = policy.decision === "allow";
    if (policy.decision === "block") return blocked(policy.reason);
    if (policy.decision === "ask") allowed = await services.approve(action, policy.reason, signal);
    if (policy.decision === "review") {
      let verdict: Verdict;
      try {
        verdict = await services.classify(action, signal);
      } catch {
        signal.throwIfAborted();
        verdict = { decision: "ask", reason: "Automatic review was unavailable or invalid. Inspect the complete action before approving." };
      }
      if (verdict.decision === "deny") return blocked("Reviewer rejected this action. Ask the user for a different approach.");
      allowed = verdict.decision === "allow" || (verdict.decision === "ask" && await services.approve(action, verdict.reason, signal));
    }
    signal.throwIfAborted();
    if (JSON.stringify(input) !== original || JSON.stringify(action.input) !== original) return blocked("Arguments changed during review.");
    return allowed ? undefined : blocked("No explicit approval for this action (rejected, cancelled, unavailable, or expired).");
  } catch {
    return blocked("Review cancelled or failed; action was not executed.");
  }
}
