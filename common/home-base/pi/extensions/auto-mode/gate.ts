import { actionForTool, evaluatePolicy, type Action, type PolicyDecision } from "./policy.ts";

export interface Verdict { decision: "allow" | "ask" | "deny"; reason: string }
export interface GateServices {
  classify(action: Action, signal: AbortSignal): Promise<Verdict>;
  approve(action: Action, reason: string, signal: AbortSignal): Promise<boolean>;
  policy?: (action: Action) => PolicyDecision;
  isCurrent?: () => boolean | Promise<boolean>;
  scope?: (action: Action, signal: AbortSignal) => Promise<(() => boolean | Promise<boolean>) | undefined>;
  /** A reason here forces single-use human approval; the classifier may still deny but never allow. */
  escalate?: (action: Action) => string | undefined;
}
/** `denied` marks refusals of the requested effect (not procedural failures) for the caller's ledger. */
export type GateResult = undefined | { block: true; reason: string; denied?: true };

/** Every approval is consumed by this call; nothing is cached across executions. */
export async function guardTool(
  toolName: string, input: Record<string, unknown>, cwd: string,
  services: GateServices, signal: AbortSignal,
): Promise<GateResult> {
  const blocked = (reason: string, denied = false): GateResult => ({
    block: true, reason: `Auto Mode: ${reason} Do not retry equivalent actions through another tool or agent to evade review.`,
    ...(denied ? { denied: true as const } : {}),
  });
  try {
    signal.throwIfAborted();
    const original = JSON.stringify(input);
    const action = actionForTool(toolName, input, cwd);
    const policy = (services.policy ?? evaluatePolicy)(action);
    if (policy.decision === "block") return blocked(policy.reason, policy.denial === true);
    const escalation = services.escalate?.(action);
    const review = async (): Promise<Verdict> => {
      try { return await services.classify(action, signal); }
      catch {
        signal.throwIfAborted();
        return { decision: "ask", reason: "Automatic review was unavailable or invalid. Inspect the complete action before approving." };
      }
    };
    let allowed = false;
    const scoped = !escalation && policy.decision !== "allow" ? await services.scope?.(action, signal) : undefined;
    if (scoped) allowed = true;
    // Local "ask" actions are never sent to the classifier, including escalated ones.
    else if (policy.decision === "ask") allowed = await services.approve(action, escalation ? `${escalation} ${policy.reason}` : policy.reason, signal);
    else if (escalation) {
      const verdict = await review();
      if (verdict.decision === "deny") return blocked("Reviewer rejected this action. Ask the user for a different approach.", true);
      allowed = await services.approve(action, `${escalation} Reviewer: ${verdict.reason}`, signal);
    } else if (policy.decision === "review") {
      const verdict = await review();
      if (verdict.decision === "deny") return blocked("Reviewer rejected this action. Ask the user for a different approach.", true);
      allowed = verdict.decision === "allow" || (verdict.decision === "ask" && await services.approve(action, verdict.reason, signal));
    } else allowed = true;
    signal.throwIfAborted();
    if (scoped && !await scoped()) return blocked("Task scope was revoked or changed before execution.");
    if (services.isCurrent && !await services.isCurrent()) return blocked("Task, session, or branch changed during review; a fresh review is required.");
    signal.throwIfAborted();
    if (JSON.stringify(input) !== original || JSON.stringify(action.input) !== original) return blocked("Arguments changed during review.");
    return allowed ? undefined : blocked("No explicit approval for this action (rejected, cancelled, unavailable, or expired).", true);
  } catch {
    return blocked("Review cancelled or failed; action was not executed.");
  }
}
