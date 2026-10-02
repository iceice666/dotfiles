import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { registerBackgroundTask } from "../index";
import type { PlanFactory } from "../manager";

// Keep lifecycle fixtures deterministic with a minimal explicit environment.
export const fixturePlan: PlanFactory = ({ command, cwd }) => ({
  command: "bash",
  args: ["--noprofile", "--norc", "-c", command],
  options: { cwd, env: { PATH: process.env.PATH } },
});

export default function (pi: ExtensionAPI) {
  registerBackgroundTask(pi, { plan: fixturePlan });
}
