import { createState } from "ags";
import { execAsync } from "ags/process";
import { readFile } from "ags/file";
import GLib from "gi://GLib";

type Config = {
  stateBinary: string;
  stateConfig: string;
  ccCtl: string;
  ccCmd: string;
  ccWifi: string;
  icons: Record<string, string>;
};
export type Values = Record<string, string>;

export const directory = GLib.build_filenamev([
  GLib.get_user_config_dir(),
  "ags",
]);
export const config: Config = JSON.parse(
  readFile(GLib.build_filenamev([directory, "config.json"])),
);
export const [state, setState] = createState<Values>({});
export const [groupsState, setGroups] = createState("[]");
export const [historyState, setHistory] = createState("[]");
const switchStates = Object.fromEntries(
  ["wifi", "bt", "dnd", "dark", "lid"].map((key) => [key, createState("off")]),
);
export const switches = Object.fromEntries(
  Object.entries(switchStates).map(([key, pair]) => [key, pair[0]]),
);
export const icon = (name: string) => config.icons[name] || "image-missing";
export const value = (key: string, fallback = "") =>
  state((s) => s[key] ?? fallback);

export function patch(line: string) {
  try {
    const data = JSON.parse(line);
    if (data && typeof data === "object" && !Array.isArray(data)) {
      // The Rust helper's protocol is string-valued; reject unexpected data.
      const values = Object.fromEntries(
        Object.entries(data).filter(([, value]) => typeof value === "string"),
      ) as Values;
      setState((current) => ({ ...current, ...values }));
      if (typeof values.niri_groups === "string") setGroups(values.niri_groups);
      if (typeof values.notifications_history === "string")
        setHistory(values.notifications_history);
    }
  } catch {
    console.error("invalid shell-state event");
  }
}

export function command(
  args: string[],
  onOutput?: (out: string) => void,
  onError?: () => void,
) {
  return execAsync(args)
    .then((out) => {
      if (onOutput) onOutput(out);
      else if (out.trim()) patch(out);
    })
    .catch(() => {
      // Never log argv or stderr: Wi-Fi commands can carry credentials.
      if (args[0] !== config.ccWifi)
        console.error("shell action failed", args[0]);
      onError?.();
    });
}
export const shell = (...args: string[]) =>
  command([config.stateBinary, "--config-file", config.stateConfig, ...args]);
export function refreshSwitch(key: string) {
  return command([config.ccCtl, "state", key], (out) =>
    switchStates[key][1](out.trim()),
  );
}
export function toggleSwitch(key: string) {
  return command([config.ccCtl, "toggle", key], () => {
    void refreshSwitch(key);
  });
}
