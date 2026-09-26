import { Accessor, createState, For, With } from "ags";
import Gtk from "gi://Gtk?version=4.0";
import Gio from "gi://Gio";
import {
  command,
  config,
  historyState,
  icon,
  shell,
  state,
  switches,
  toggleSwitch,
  value,
} from "./state";

type Network = {
  ssid: string;
  active: boolean;
  known: boolean;
  security: string;
  signal: number;
};
type Notification = {
  key: string;
  class: string;
  summary: string;
  preview: string;
  source: string;
  body: string;
  unread: boolean;
};
const vertical = Gtk.Orientation.VERTICAL;
const [view, setView] = createState("home");
const [networks, setNetworks] = createState<Network[]>([]);
const [wifiTarget, setWifiTarget] = createState("");
const [wifiPassword, setWifiPassword] = createState("");
const [wifiError, setWifiError] = createState("");
const [wifiBusy, setWifiBusy] = createState(false);
const [expanded, setExpanded] = createState("");

function wifi(args: string[], clearError = true) {
  if (wifiBusy()) return;
  if (clearError) setWifiError("");
  setWifiBusy(true);
  command(
    [config.ccWifi, ...args],
    (out) => {
      setWifiBusy(false);
      try {
        const rows = JSON.parse(out);
        if (!Array.isArray(rows)) throw new Error("invalid scan");
        setNetworks(rows.filter((row) => typeof row?.ssid === "string"));
      } catch {
        setWifiError("Could not read Wi-Fi networks. Try scanning again.");
      }
    },
    () => {
      setWifiBusy(false);
      setWifiError("Wi-Fi operation failed; check the password or connection.");
    },
  );
}
export function refreshWifi() {
  if (view() === "wifi" && !wifiTarget()) wifi(["scan"], false);
}
export function openView(name: string) {
  if (name !== "wifi") {
    setWifiTarget("");
    setWifiPassword("");
  }
  setView(name);
  if (name === "wifi") wifi(["scan"]);
}
export function resetControl() {
  setWifiPassword("");
  setWifiTarget("");
  setExpanded("");
  setView("home");
}
function connectWifi(ssid: string) {
  if (wifiBusy()) return;
  wifi(["connect", ssid, wifiPassword()]);
  setWifiPassword("");
  setWifiTarget("");
}
function Picture({
  name,
  path,
  size = 22,
}: {
  name?: string;
  path?: string | Accessor<string>;
  size?: number;
}) {
  const file = path || icon(name || "appPlaceholder");
  const asIcon = (filename: string) =>
    filename.startsWith("/")
      ? Gio.FileIcon.new(Gio.File.new_for_path(filename))
      : Gio.ThemedIcon.new(filename);
  return (
    <image
      gicon={typeof file === "string" ? asIcon(file) : file(asIcon)}
      pixelSize={size}
      halign={Gtk.Align.CENTER}
      valign={Gtk.Align.CENTER}
    />
  );
}
function Action({
  label,
  click,
  cssClass = "",
  iconName,
}: {
  label: string;
  click: () => void;
  cssClass?: string;
  iconName?: string;
}) {
  return (
    <button
      cssClasses={["cc-action", ...cssClass.split(" ").filter(Boolean)]}
      tooltipText={label}
      onClicked={click}
    >
      <box spacing={10}>
        {iconName && <Picture name={iconName} size={20} />}
        <label label={label} />
      </box>
    </button>
  );
}
function Tile({
  label,
  keyName,
  iconName,
  detail,
  subtitle,
}: {
  label: string;
  keyName: string;
  iconName: string;
  detail?: () => void;
  subtitle?: Accessor<string>;
}) {
  return (
    <box
      cssClasses={switches[keyName]((s) => [
        "cc-toggle",
        ...(s === "on" ? ["on"] : []),
        ...(detail ? ["split"] : []),
      ])}
      hexpand
    >
      <button
        cssClasses={["tile-main"]}
        hexpand
        tooltipText={`Toggle ${label}`}
        onClicked={() => toggleSwitch(keyName)}
      >
        <box spacing={12}>
          <Picture name={iconName} />
          <box
            orientation={vertical}
            spacing={3}
            valign={Gtk.Align.CENTER}
            hexpand
          >
            <label cssClasses={["tile-title"]} xalign={0} label={label} />
            <label
              cssClasses={["secondary"]}
              xalign={0}
              maxWidthChars={14}
              ellipsize={3}
              label={
                subtitle ||
                switches[keyName]((s) => (s === "on" ? "On" : "Off"))
              }
            />
          </box>
        </box>
      </button>
      {detail && (
        <button
          cssClasses={["tile-detail"]}
          tooltipText={`${label} settings`}
          onClicked={detail}
        >
          <image iconName="go-next-symbolic" pixelSize={16} />
        </button>
      )}
    </box>
  );
}
function Volume({ device }: { device: "speaker" | "mic" }) {
  const field = `audio_${device}`;
  return (
    <box cssClasses={["cc-slider-row"]} spacing={12}>
      <button
        cssClasses={["slider-icon"]}
        valign={Gtk.Align.CENTER}
        tooltipText={value(`${field}_text`, `Mute ${device}`)}
        onClicked={() => shell("audio", "toggle", device)}
      >
        <Picture
          path={value(
            `${field}_icon`,
            icon(device === "mic" ? "micActive" : "speakerHigh"),
          )}
        />
      </button>
      <box orientation={vertical} hexpand spacing={2}>
        <box spacing={8}>
          <label
            cssClasses={["slider-label"]}
            xalign={0}
            hexpand
            maxWidthChars={26}
            ellipsize={3}
            label={value(
              `${field}_device`,
              device === "mic" ? "Microphone" : "Volume",
            )}
          />
          <label
            cssClasses={["secondary"]}
            label={value(`${field}_percent`, "0%")}
          />
        </box>
        <slider
          cssClasses={["cc-scale"]}
          hexpand
          min={0}
          max={1}
          value={state((s) => Number(s[`${field}_value`] || 0) / 100)}
          onChangeValue={(_self, _scroll, next) => {
            // change-value is user input; state-driven adjustment updates never send commands.
            shell(
              "audio",
              "set",
              device,
              String(Math.round(Math.max(0, Math.min(1, next)) * 100)),
            );
            return false;
          }}
        />
      </box>
    </box>
  );
}
function Brightness() {
  return (
    <box cssClasses={["cc-slider-row"]} spacing={12}>
      <box cssClasses={["slider-icon"]} valign={Gtk.Align.CENTER} homogeneous>
        <Picture name="brightness" />
      </box>
      <box orientation={vertical} hexpand spacing={2}>
        <box spacing={8}>
          <label
            cssClasses={["slider-label"]}
            xalign={0}
            hexpand
            label="Brightness"
          />
          <label
            cssClasses={["secondary"]}
            label={value("brightness_text", "0%")}
          />
        </box>
        <slider
          cssClasses={["cc-scale"]}
          hexpand
          min={0.01}
          max={1}
          value={state((s) => Number(s.brightness_value || 1) / 100)}
          onChangeValue={(_self, _scroll, next) => {
            shell(
              "brightness",
              "set",
              String(Math.round(Math.max(0.01, Math.min(1, next)) * 100)),
            );
            return false;
          }}
        />
      </box>
    </box>
  );
}
function Home() {
  return (
    <box cssClasses={["cc-page"]} orientation={vertical} spacing={12}>
      <box
        cssClasses={["cc-quick-settings"]}
        orientation={vertical}
        spacing={8}
      >
        <box homogeneous spacing={8}>
          <Tile
            label="Wi-Fi"
            keyName="wifi"
            iconName="network"
            subtitle={value("network_label", "Offline")}
            detail={() => openView("wifi")}
          />
          <Tile
            label="Bluetooth"
            keyName="bt"
            iconName="bluetooth"
            detail={() => command([config.ccCmd, "open-bluetooth"])}
          />
        </box>
        <box homogeneous spacing={8}>
          <Tile label="Do Not Disturb" keyName="dnd" iconName="notification" />
          <Tile label="Dark Style" keyName="dark" iconName="darkMode" />
        </box>
        <box homogeneous spacing={8}>
          <Tile label="Lid Sleep" keyName="lid" iconName="lidSleep" />
          <button
            cssClasses={["cc-shortcut"]}
            onClicked={() => openView("sound")}
            tooltipText="Sound settings"
          >
            <box spacing={12}>
              <Picture name="speakerHigh" />
              <label hexpand xalign={0} label="Sound" />
              <image iconName="go-next-symbolic" pixelSize={16} />
            </box>
          </button>
        </box>
      </box>
      <box
        cssClasses={["cc-section", "cc-sliders"]}
        orientation={vertical}
        spacing={12}
      >
        <Volume device="speaker" />
        <Brightness />
      </box>
      <box
        cssClasses={["cc-section", "cc-media"]}
        orientation={vertical}
        spacing={12}
        visible={state((s) => !!s.media_text)}
      >
        <box spacing={12}>
          <box cssClasses={["media-art"]} valign={Gtk.Align.CENTER} homogeneous>
            <Picture name="media" size={28} />
          </box>
          <box orientation={vertical} spacing={4} hexpand>
            <label cssClasses={["secondary"]} xalign={0} label="NOW PLAYING" />
            <label
              cssClasses={["heading"]}
              xalign={0}
              maxWidthChars={38}
              lines={2}
              ellipsize={3}
              wrap
              label={value("media_text")}
            />
          </box>
        </box>
        <box homogeneous spacing={8}>
          <Action label="Previous" click={() => shell("media", "previous")} />
          <Action
            label="Play / Pause"
            cssClass="primary"
            click={() => shell("media", "play-pause")}
          />
          <Action label="Next" click={() => shell("media", "next")} />
        </box>
      </box>
      <button
        cssClasses={["cc-notifications-link"]}
        onClicked={() => openView("notifications")}
      >
        <box spacing={12}>
          <Picture name="notification" size={20} />
          <label hexpand xalign={0} label="Notifications" />
          <label
            cssClasses={["cc-count"]}
            label={value("notifications_history_count", "0")}
          />
          <image iconName="go-next-symbolic" pixelSize={16} />
        </box>
      </button>
    </box>
  );
}
function Wifi() {
  return (
    <box cssClasses={["cc-page"]} orientation={vertical} spacing={12}>
      <box homogeneous spacing={8}>
        <Tile label="Wi-Fi" keyName="wifi" iconName="network" />
        <button
          cssClasses={["cc-action"]}
          sensitive={wifiBusy((busy) => !busy)}
          onClicked={() => wifi(["rescan"])}
        >
          <label
            label={wifiBusy((busy) => (busy ? "Working…" : "Scan networks"))}
          />
        </button>
      </box>
      <label
        cssClasses={["wifi-error"]}
        xalign={0}
        wrap
        maxWidthChars={46}
        visible={wifiError(Boolean)}
        label={wifiError}
      />
      <box cssClasses={["cc-section"]} spacing={8}>
        <box
          orientation={vertical}
          spacing={3}
          hexpand
          valign={Gtk.Align.CENTER}
        >
          <label
            cssClasses={["secondary"]}
            xalign={0}
            label="CURRENT CONNECTION"
          />
          <label
            xalign={0}
            ellipsize={3}
            maxWidthChars={26}
            label={value("network_label", "Offline")}
          />
        </box>
        <button
          cssClasses={["cc-action"]}
          sensitive={wifiBusy((busy) => !busy)}
          onClicked={() => wifi(["disconnect"])}
        >
          <label label="Disconnect" />
        </button>
      </box>
      <scrolledwindow
        cssClasses={["scroll-area"]}
        hscrollbarPolicy={Gtk.PolicyType.NEVER}
        heightRequest={280}
      >
        <box orientation={vertical} spacing={6}>
          <label
            cssClasses={["empty-state"]}
            visible={networks((rows) => rows.length === 0)}
            label="No networks found. Try scanning again."
            wrap
          />
          <For each={networks}>
            {(net) => (
              <box orientation={vertical}>
                <button
                  cssClasses={["wifi-row", ...(net.active ? ["active"] : [])]}
                  sensitive={wifiBusy((busy) => !busy)}
                  onClicked={() => {
                    if (net.known || !net.security) wifi(["connect", net.ssid]);
                    else {
                      setWifiTarget(wifiTarget() === net.ssid ? "" : net.ssid);
                      setWifiPassword("");
                    }
                  }}
                >
                  <box spacing={12}>
                    <Picture name="network" size={20} />
                    <box orientation={vertical} hexpand spacing={3}>
                      <label
                        xalign={0}
                        maxWidthChars={26}
                        ellipsize={3}
                        label={net.ssid}
                      />
                      <label
                        cssClasses={["secondary"]}
                        xalign={0}
                        label={
                          net.active
                            ? "Connected"
                            : net.known
                              ? "Saved network"
                              : net.security
                                ? "Secured"
                                : "Open network"
                        }
                      />
                    </box>
                    <label
                      cssClasses={["secondary"]}
                      label={`${net.signal}%`}
                    />
                  </box>
                </button>
                <With value={wifiTarget}>
                  {(target) =>
                    target === net.ssid ? (
                      <box cssClasses={["wifi-password"]} spacing={8}>
                        <entry
                          hexpand
                          visibility={false}
                          text={wifiPassword}
                          placeholderText="Password"
                          onChanged={(self) => setWifiPassword(self.text)}
                          onActivate={() => connectWifi(net.ssid)}
                        />
                        <Action
                          label="Join"
                          cssClass="primary"
                          click={() => connectWifi(net.ssid)}
                        />
                      </box>
                    ) : (
                      <box />
                    )
                  }
                </With>
              </box>
            )}
          </For>
        </box>
      </scrolledwindow>
    </box>
  );
}
function Notifications() {
  const rows = historyState((snapshot): Notification[] => {
    try {
      const parsed = JSON.parse(snapshot || "[]");
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  });
  return (
    <box cssClasses={["cc-page"]} orientation={vertical} spacing={12}>
      <box spacing={8}>
        <label
          cssClasses={["heading"]}
          hexpand
          xalign={0}
          label="Recent notifications"
        />
        <label
          cssClasses={["cc-count"]}
          label={value("notifications_history_count", "0")}
        />
        <Action
          label="Clear"
          iconName="clear"
          click={() => command([config.ccCmd, "clear-notifications"])}
        />
      </box>
      <scrolledwindow
        cssClasses={["scroll-area"]}
        hscrollbarPolicy={Gtk.PolicyType.NEVER}
        heightRequest={360}
      >
        <box orientation={vertical} spacing={8}>
          <label
            cssClasses={["empty-state"]}
            visible={rows((items) => !items.length)}
            label="You're all caught up"
          />
          <For each={rows}>
            {(item) => (
              <box
                cssClasses={(item.class || "cc-notification-row").split(" ")}
                orientation={vertical}
              >
                <button
                  onClicked={() =>
                    setExpanded(expanded() === item.key ? "" : item.key)
                  }
                >
                  <box spacing={10}>
                    <label
                      cssClasses={["unread-dot"]}
                      visible={item.unread}
                      label="●"
                    />
                    <box orientation={vertical} hexpand spacing={5}>
                      <label
                        cssClasses={["secondary"]}
                        xalign={0}
                        label={item.source === "active" ? "Now" : "History"}
                      />
                      <label
                        cssClasses={["heading"]}
                        xalign={0}
                        maxWidthChars={36}
                        ellipsize={3}
                        label={item.summary}
                      />
                      <label
                        xalign={0}
                        maxWidthChars={42}
                        lines={2}
                        ellipsize={3}
                        wrap
                        label={item.preview}
                      />
                    </box>
                    <image
                      iconName={expanded((key) =>
                        key === item.key
                          ? "pan-up-symbolic"
                          : "pan-down-symbolic",
                      )}
                      pixelSize={16}
                    />
                  </box>
                </button>
                <With value={expanded}>
                  {(key) =>
                    key === item.key ? (
                      <label
                        cssClasses={["notification-body"]}
                        xalign={0}
                        maxWidthChars={46}
                        wrap
                        selectable
                        label={item.body || "No details"}
                      />
                    ) : (
                      <box />
                    )
                  }
                </With>
              </box>
            )}
          </For>
        </box>
      </scrolledwindow>
    </box>
  );
}
function Power() {
  return (
    <box
      cssClasses={["cc-page", "cc-session"]}
      orientation={vertical}
      spacing={8}
    >
      <label cssClasses={["secondary"]} xalign={0} label="SESSION" />
      {(
        [
          ["Lock", "lock"],
          ["Suspend", "suspend"],
          ["Log Out", "logout"],
          ["Restart", "reboot"],
          ["Shut Down", "shutdown"],
        ] as [string, string][]
      ).map(([label, action]) => (
        <Action
          label={label}
          iconName={action}
          cssClass={action === "shutdown" ? "session-destructive" : ""}
          click={() => command([config.ccCmd, action])}
        />
      ))}
    </box>
  );
}
export default function ControlContents() {
  return (
    <box cssClasses={["control-panel"]} orientation={vertical} spacing={16}>
      <box cssClasses={["cc-header"]} spacing={10}>
        <box cssClasses={["cc-battery"]} spacing={8} hexpand>
          <Picture
            path={value("battery_icon", icon("batteryUnknown"))}
            size={20}
          />
          <label
            maxWidthChars={30}
            ellipsize={3}
            label={value("battery_tooltip", "Battery --")}
          />
        </box>
        <button
          cssClasses={["cc-header-button"]}
          tooltipText="Lock"
          onClicked={() => command([config.ccCmd, "lock"])}
        >
          <Picture name="lock" size={18} />
        </button>
        <button
          cssClasses={["cc-header-button"]}
          tooltipText="Power and session"
          onClicked={() => openView("session")}
        >
          <Picture name="shutdown" size={18} />
        </button>
      </box>
      <box
        visible={view((page) => page !== "home")}
        cssClasses={["cc-page-header"]}
        spacing={10}
      >
        <button
          cssClasses={["back"]}
          tooltipText="Back to quick settings"
          onClicked={() => openView("home")}
        >
          <image iconName="go-previous-symbolic" pixelSize={20} />
        </button>
        <label
          cssClasses={["cc-page-title"]}
          xalign={0}
          label={view(
            (page) =>
              ({
                wifi: "Wi-Fi",
                sound: "Sound",
                notifications: "Notifications",
                session: "Power & Session",
              })[page] || "Quick Settings",
          )}
        />
      </box>
      <With value={view}>
        {(page) =>
          page === "wifi" ? (
            <Wifi />
          ) : page === "sound" ? (
            <box
              cssClasses={["cc-page", "cc-section"]}
              orientation={vertical}
              spacing={16}
            >
              <Volume device="speaker" />
              <Volume device="mic" />
              <Action
                label="Audio Settings"
                iconName="speakerHigh"
                click={() => shell("open-pavucontrol")}
              />
            </box>
          ) : page === "notifications" ? (
            <Notifications />
          ) : page === "session" ? (
            <Power />
          ) : (
            <Home />
          )
        }
      </With>
    </box>
  );
}
