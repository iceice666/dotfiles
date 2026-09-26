import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { registerBackgroundTask } from "../index";
import type { PlanFactory } from "../manager";

// Lifecycle tests exercise the registry, not the platform sandbox backend.
// Only this explicit test fixture supplies an unsandboxed process plan.
export const fixturePlan: PlanFactory = ({ command, cwd, workspace }) => ({
  command: "bash",
  args: ["-c", command],
  options: { cwd, env: { PATH: process.env.PATH, FIXTURE_WORKSPACE: workspace } },
});

export default function (pi: ExtensionAPI) {
  registerBackgroundTask(pi, { plan: fixturePlan });
}
