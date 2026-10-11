import app from "ags/gtk4/app";
import { Astal, Gtk } from "ags/gtk4";
import { createState, onCleanup } from "ags";
import GLib from "gi://GLib";
import Gio from "gi://Gio";
import Cairo from "cairo";
import { icon } from "./state";

type Osd = { title: string; value: number; icon: string; muted: boolean };
const [current, setCurrent] = createState<Osd>({
  title: "Volume",
  value: 0,
  icon: icon("speakerHigh"),
  muted: false,
});
const [visible, setVisible] = createState(false);
let timer: number | null = null;

function clearTimer() {
  if (timer !== null) GLib.source_remove(timer);
  timer = null;
}

// Only explicit media-key requests show an OSD, never ordinary state patches.
export function handleOsdRequest(args: string[]): boolean {
  if (args.length !== 3 || args[0] !== "osd") return false;
  const kind = args[1];
  if (!["speaker", "mic", "brightness"].includes(kind)) return false;
  try {
    const data = JSON.parse(args[2]);
    if (!data || typeof data !== "object" || Array.isArray(data)) return false;
    const key =
      kind === "brightness" ? "brightness_value" : `audio_${kind}_value`;
    const raw = data[key];
    if (typeof raw !== "string" || !raw.trim()) return false;
    const value = Number(raw);
    if (!Number.isFinite(value) || value < 0 || value > 100) return false;
    const classes = kind === "brightness" ? "" : data[`audio_${kind}_class`];
    if (typeof classes !== "string") return false;
    const muted = classes.split(/\s+/).includes("muted");
    const title =
      kind === "brightness"
        ? "Brightness"
        : kind === "mic" ? "Microphone" : "Volume";
    const image =
      kind === "brightness"
        ? "brightness"
        : kind === "mic"
          ? (muted ? "micMuted" : "micActive")
          : muted || value === 0
            ? "speakerMuted"
            : value < 50 ? "speakerLow" : "speakerHigh";
    setCurrent({
      title: muted ? `${title} · Muted` : title,
      value,
      icon: icon(image),
      muted,
    });
    clearTimer();
    setVisible(true);
    timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1500, () => {
      timer = null;
      setVisible(false);
      return GLib.SOURCE_REMOVE;
    });
    return true;
  } catch {
    return false;
  }
}

/** No fixed output: the compositor chooses the focused monitor on each map. */
export function OsdWindow() {
  const win = (
    <window
      name="media-osd"
      namespace="framework-ags-osd"
      class="osd-window"
      application={app}
      anchor={Astal.WindowAnchor.BOTTOM}
      marginBottom={80}
      layer={Astal.Layer.OVERLAY}
      exclusivity={Astal.Exclusivity.IGNORE}
      keymode={Astal.Keymode.NONE}
      focusable={false}
      visible={visible}
    >
      <box class="osd-card" spacing={16}>
        <image
          class="osd-icon"
          gicon={current((item) =>
            Gio.FileIcon.new(Gio.File.new_for_path(item.icon)),
          )}
          pixelSize={32}
        />
        <box orientation={Gtk.Orientation.VERTICAL} spacing={10} hexpand>
          <box spacing={24}>
            <label
              class="osd-title"
              label={current((item) => item.title)}
              xalign={0}
              hexpand
            />
            <label
              class="osd-value"
              label={current((item) => `${Math.round(item.value)}%`)}
            />
          </box>
          <Gtk.ProgressBar
            cssClasses={["osd-progress"]}
            fraction={current((item) => (item.muted ? 0 : item.value / 100))}
          />
        </box>
      </box>
    </window>
  ) as Astal.Window;
  // A visual hint must not intercept pointer input or steal keyboard focus.
  win.connect("realize", () =>
    win.get_surface()?.set_input_region(new Cairo.Region()),
  );
  onCleanup(() => {
    clearTimer();
    setVisible(false);
  });
  return win;
}
