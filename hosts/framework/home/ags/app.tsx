import { App, Astal, Gtk, Gdk } from "astal/gtk3";
import { Variable, bind } from "astal";
import { execAsync, subprocess } from "astal/process";
import { readFile } from "astal/file";
import Tray from "gi://AstalTray";
import GLib from "gi://GLib";
import Gio from "gi://Gio";
import System from "system";

type Config = {
  stateBinary: string;
  stateConfig: string;
  ccCtl: string;
  ccCmd: string;
  ccWifi: string;
  icons: Record<string, string>;
};
type Values = Record<string, string>;
type WindowItem = {
  id: number;
  title: string;
  focused: boolean;
  icon_path: string;
};
type Group = {
  monitor: string;
  workspaces: Array<{ label: string; windows: WindowItem[] }>;
};
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

const directory = GLib.build_filenamev([GLib.get_user_config_dir(), "ags"]);
const config: Config = JSON.parse(
  readFile(GLib.build_filenamev([directory, "config.json"])),
);
const state = Variable<Values>({});
const groupsState = Variable("[]");
const historyState = Variable("[]");
const view = Variable("home");
const networks = Variable<Network[]>([]);
const wifiTarget = Variable("");
const wifiPassword = Variable("");
const wifiError = Variable("");
const expanded = Variable("");
const switches = Object.fromEntries(
  ["wifi", "bt", "dnd", "dark", "lid"].map((key) => [key, Variable("off")]),
) as Record<string, ReturnType<typeof Variable<string>>>;
const icon = (name: string) => config.icons[name] || "image-missing";
const value = (key: string, fallback = "") => state((s) => s[key] ?? fallback);
function patch(line: string) {
  try {
    const data = JSON.parse(line);
    if (data && typeof data === "object" && !Array.isArray(data)) {
      state.set({ ...state.get(), ...data });
      if (typeof data.niri_groups === "string")
        groupsState.set(data.niri_groups);
      if (typeof data.notifications_history === "string")
        historyState.set(data.notifications_history);
    }
  } catch (error) {
    console.error("invalid shell-state event", error);
  }
}
function command(args: string[], onOutput?: (out: string) => void) {
  execAsync(args)
    .then((out) => {
      if (onOutput) onOutput(out);
      else if (out.trim()) patch(out);
    })
    .catch((error) => {
      if (args[0] === config.ccWifi)
        wifiError.set(
          "Wi-Fi operation failed; check the password or connection.",
        );
      else console.error(args[0], error);
    });
}
const shell = (...args: string[]) =>
  command([config.stateBinary, "--config-file", config.stateConfig, ...args]);
function scan(rescan = false) {
  wifiError.set("");
  command([config.ccWifi, rescan ? "rescan" : "scan"], (out) => {
    try {
      const rows = JSON.parse(out);
      networks.set(Array.isArray(rows) ? rows : []);
    } catch (error) {
      console.error("invalid Wi-Fi scan", error);
    }
  });
}
function refreshSwitch(key: string) {
  command([config.ccCtl, "state", key], (out) => switches[key].set(out.trim()));
}
function toggleSwitch(key: string) {
  command([config.ccCtl, "toggle", key], () => refreshSwitch(key));
}
function openView(name: string) {
  if (name !== "wifi") {
    wifiTarget.set("");
    wifiPassword.set("");
  }
  view.set(name);
  if (name === "wifi") scan();
}
function Picture({
  name,
  path,
  size = 20,
}: {
  name?: string;
  path?: string;
  size?: number;
}) {
  const file = path || icon(name || "appPlaceholder");
  return (
    <icon
      gicon={Gio.FileIcon.new(Gio.File.new_for_path(file))}
      css={`
        font-size: ${size}px;
      `}
    />
  );
}
function Action({
  label,
  click,
  className = "",
  iconName,
}: {
  label: string;
  click: () => void;
  className?: string;
  iconName?: string;
}) {
  return (
    <button className={className} tooltipText={label} onClicked={click}>
      <box spacing={5}>
        {iconName && <Picture name={iconName} />}
        <label label={label} />
      </box>
    </button>
  );
}
function Tile({
  label,
  keyName,
  iconName,
  right,
}: {
  label: string;
  keyName: string;
  iconName: string;
  right?: () => void;
}) {
  return (
    <button
      className={switches[keyName]((s) =>
        s === "on" ? "cc-toggle on" : "cc-toggle",
      )}
      onClick={(_, event) => {
        if (event.button === 3 && right) right();
        else toggleSwitch(keyName);
      }}
    >
      <box spacing={8}>
        <Picture name={iconName} />
        <box vertical>
          <label xalign={0} label={label} />
          <label
            className="secondary"
            xalign={0}
            label={switches[keyName]((s) => (s === "on" ? "On" : "Off"))}
          />
        </box>
      </box>
    </button>
  );
}
function Volume({
  device,
  compact = false,
}: {
  device: "speaker" | "mic";
  compact?: boolean;
}) {
  const field = `audio_${device}`;
  return (
    <box className="cc-slider-row" spacing={10}>
      <button
        className="slider-icon"
        valign={Gtk.Align.CENTER}
        tooltipText={value(`${field}_text`)}
        onClick={(_, event) => {
          if (event.button === 3) shell("open-pavucontrol");
          else if (compact) openView("sound");
          else shell("audio", "toggle", device);
        }}
      >
        <icon
          gicon={value(
            `${field}_icon`,
            icon(device === "mic" ? "micActive" : "speakerHigh"),
          ).as((file) => Gio.FileIcon.new(Gio.File.new_for_path(file)))}
          css="font-size: 22px;"
        />
      </button>
      <box vertical hexpand>
        <box>
          <label xalign={0} hexpand label={value(`${field}_device`, device)} />
          <label label={value(`${field}_percent`, "0%")} />
        </box>
        <slider
          className="cc-scale"
          hexpand
          min={0}
          max={1}
          value={state((s) => Number(s[`${field}_value`] || 0) / 100)}
          onDragged={(self) =>
            shell("audio", "set", device, String(Math.round(self.value * 100)))
          }
        />
      </box>
    </box>
  );
}
function Brightness() {
  return (
    <box className="cc-slider-row" spacing={10}>
      <box className="slider-icon" valign={Gtk.Align.CENTER} homogeneous>
        <Picture name="brightness" size={22} />
      </box>
      <box vertical hexpand>
        <box>
          <label xalign={0} hexpand label="Display" />
          <label label={value("brightness_text", "0%")} />
        </box>
        <slider
          className="cc-scale"
          hexpand
          min={0.01}
          max={1}
          value={state((s) => Number(s.brightness_value || 1) / 100)}
          onDragged={(self) =>
            shell("brightness", "set", String(Math.round(self.value * 100)))
          }
        />
      </box>
    </box>
  );
}
function Home() {
  return (
    <box className="cc-page" vertical spacing={10}>
      <box homogeneous spacing={8}>
        <box className="cc-toggle split">
          <button onClicked={() => toggleSwitch("wifi")}>
            <Picture name="network" />
          </button>
          <button hexpand onClicked={() => openView("wifi")}>
            <box vertical>
              <label xalign={0} label="Wi-Fi ›" />
              <label
                className="secondary"
                xalign={0}
                label={value("network_label", "Offline")}
              />
            </box>
          </button>
        </box>
        <Tile
          label="Bluetooth"
          keyName="bt"
          iconName="bluetooth"
          right={() => command([config.ccCmd, "open-bluetooth"])}
        />
      </box>
      <box homogeneous spacing={8}>
        <Tile label="Silence" keyName="dnd" iconName="notification" />
        <Tile label="Dark" keyName="dark" iconName="darkMode" />
      </box>
      <box homogeneous spacing={8}>
        <Tile label="Lid Sleep" keyName="lid" iconName="lidSleep" />
        <box />
      </box>
      <box className="cc-section" vertical spacing={8}>
        <Volume device="speaker" compact />
        <Brightness />
      </box>
      <box
        className="cc-section"
        vertical
        spacing={8}
        visible={state((s) => !!s.media_text)}
      >
        <label xalign={0} className="heading" label="Now Playing" />
        <label xalign={0} maxWidthChars={44} wrap label={value("media_text")} />
        <box homogeneous spacing={8}>
          <Action label="Prev" click={() => shell("media", "previous")} />
          <Action
            label="Play"
            className="primary"
            click={() => shell("media", "play-pause")}
          />
          <Action label="Next" click={() => shell("media", "next")} />
        </box>
      </box>
      <box className="cc-section" vertical>
        <Action
          label="Sound ›"
          click={() => openView("sound")}
          iconName="speakerHigh"
        />
        <Action
          label="Notifications ›"
          click={() => openView("notifications")}
          iconName="notification"
        />
        <Action
          label="Power ›"
          click={() => openView("session")}
          iconName="lock"
        />
      </box>
    </box>
  );
}
function Wifi() {
  return (
    <box className="cc-page" vertical spacing={10}>
      <box className="cc-section" vertical spacing={8}>
        <label
          className="wifi-error"
          xalign={0}
          visible={wifiError((message) => !!message)}
          label={wifiError()}
        />
        <box spacing={8}>
          <Tile label="Wi-Fi" keyName="wifi" iconName="network" />
          <Action label="Scan" click={() => scan(true)} />
        </box>
        <box>
          <label hexpand xalign={0} label={value("network_label", "Offline")} />
          <Action
            label="Disconnect"
            click={() =>
              command([config.ccWifi, "disconnect"], (out) => {
                try {
                  networks.set(JSON.parse(out));
                } catch {
                  scan();
                }
              })
            }
          />
        </box>
        <scrollable
          className="scroll-area"
          hscroll={Gtk.PolicyType.NEVER}
          heightRequest={250}
        >
          <box vertical spacing={4}>
            {networks((rows) =>
              rows.map((net) => (
                <box vertical>
                  <button
                    className={net.active ? "wifi-row active" : "wifi-row"}
                    onClicked={() => {
                      if (net.known || !net.security)
                        command([config.ccWifi, "connect", net.ssid], (out) => {
                          try {
                            networks.set(JSON.parse(out));
                          } catch {
                            scan();
                          }
                        });
                      else {
                        wifiTarget.set(
                          wifiTarget.get() === net.ssid ? "" : net.ssid,
                        );
                        wifiPassword.set("");
                      }
                    }}
                  >
                    <box spacing={8}>
                      <Picture name="network" size={18} />
                      <label
                        hexpand
                        xalign={0}
                        maxWidthChars={24}
                        ellipsize={3}
                        label={net.ssid}
                      />
                      <label
                        label={`${net.security ? "🔒 " : ""}${net.signal}%`}
                      />
                    </box>
                  </button>
                  {wifiTarget((target) =>
                    target === net.ssid ? (
                      <box className="wifi-password" spacing={6}>
                        <entry
                          hexpand
                          visibility={false}
                          text={wifiPassword()}
                          placeholderText="Password"
                          onChanged={(self) => wifiPassword.set(self.text)}
                          onActivate={() => connectWifi(net.ssid)}
                        />
                        <Action
                          label="Join"
                          click={() => connectWifi(net.ssid)}
                        />
                      </box>
                    ) : (
                      <box />
                    ),
                  )}
                </box>
              )),
            )}
          </box>
        </scrollable>
      </box>
    </box>
  );
}
function connectWifi(ssid: string) {
  wifiError.set("");
  command([config.ccWifi, "connect", ssid, wifiPassword.get()], (out) => {
    try {
      networks.set(JSON.parse(out));
    } catch {
      scan();
    }
  });
  wifiPassword.set("");
  wifiTarget.set("");
}
function Notifications() {
  return (
    <box className="cc-page cc-section" vertical spacing={8}>
      <box>
        <label className="heading" hexpand xalign={0} label="Recent" />
        <Action
          label="Clear"
          click={() => command([config.ccCmd, "clear-notifications"])}
        />
        <label label={value("notifications_history_count", "0")} />
      </box>
      <scrollable
        className="scroll-area"
        hscroll={Gtk.PolicyType.NEVER}
        heightRequest={250}
      >
        <box vertical spacing={6}>
          {historyState((snapshot) => {
            let rows: Notification[] = [];
            try {
              rows = JSON.parse(snapshot || "[]");
            } catch {
              /* invalid history */
            }
            return rows.length ? (
              rows.map((item) => (
                <box className={item.class || "notification-row"} vertical>
                  <button
                    onClicked={() =>
                      expanded.set(expanded.get() === item.key ? "" : item.key)
                    }
                  >
                    <box spacing={8}>
                      <label label={item.unread ? "●" : ""} />
                      <box vertical hexpand>
                        <label
                          className="heading"
                          xalign={0}
                          maxWidthChars={34}
                          ellipsize={3}
                          label={item.summary}
                        />
                        <label
                          xalign={0}
                          maxWidthChars={40}
                          wrap
                          label={item.preview}
                        />
                      </box>
                      <label
                        className="secondary"
                        label={item.source === "active" ? "Now" : "History"}
                      />
                    </box>
                  </button>
                  {expanded((key) =>
                    key === item.key ? (
                      <label
                        xalign={0}
                        maxWidthChars={46}
                        wrap
                        label={item.body || "No details"}
                      />
                    ) : (
                      <box />
                    ),
                  )}
                </box>
              ))
            ) : (
              <label xalign={0} label="No notifications" />
            );
          })}
        </box>
      </scrollable>
    </box>
  );
}
function Power() {
  return (
    <box className="cc-page cc-section" homogeneous spacing={5}>
      {(
        [
          ["Lock", "lock"],
          ["Suspend", "suspend"],
          ["Restart", "reboot"],
          ["Shut Down", "shutdown"],
          ["Log Out", "logout"],
        ] as [string, string][]
      ).map(([label, action]) => (
        <Action
          label={label}
          iconName={
            action === "shutdown"
              ? "shutdown"
              : action === "suspend"
                ? "suspend"
                : action === "reboot"
                  ? "reboot"
                  : action === "logout"
                    ? "logout"
                    : "lock"
          }
          click={() => command([config.ccCmd, action])}
        />
      ))}
    </box>
  );
}
function ControlContents() {
  return (
    <box className="control-panel" vertical spacing={10}>
      {view((page) =>
        page !== "home" ? (
          <button className="back" onClicked={() => openView("home")}>
            <label
              xalign={0}
              label={`‹  ${page === "session" ? "Power" : page[0].toUpperCase() + page.slice(1)}`}
            />
          </button>
        ) : (
          <box />
        ),
      )}
      {view((page) =>
        page === "wifi" ? (
          <Wifi />
        ) : page === "sound" ? (
          <box className="cc-page cc-section" vertical spacing={8}>
            <Volume device="speaker" />
            <Volume device="mic" />
            <Action
              label="Audio Settings"
              click={() => shell("open-pavucontrol")}
            />
          </box>
        ) : page === "notifications" ? (
          <Notifications />
        ) : page === "session" ? (
          <Power />
        ) : (
          <Home />
        ),
      )}
    </box>
  );
}

const overlays = new Map<
  Gdk.Monitor,
  { bar: Gtk.Widget; control: any; calendar: any }
>();
let windowId = 0;
function close(mon: Gdk.Monitor) {
  const windows = overlays.get(mon);
  wifiPassword.set("");
  wifiTarget.set("");
  if (windows) {
    windows.control.hide();
    windows.calendar.hide();
  }
}
function toggle(mon: Gdk.Monitor, target: "control" | "calendar") {
  const windows = overlays.get(mon);
  if (!windows) return;
  const other = target === "control" ? windows.calendar : windows.control;
  other.hide();
  const window = windows[target];
  if (window.visible) close(mon);
  else {
    wifiPassword.set("");
    wifiTarget.set("");
    if (target === "control") openView("home");
    window.show();
    window.present();
  }
}
function Popup(mon: Gdk.Monitor, kind: "control" | "calendar") {
  return (
    <window
      name={`${kind}-${windowId++}`}
      className="popup-window"
      application={App}
      gdkmonitor={mon}
      namespace={
        kind === "control"
          ? "framework-ags-control-center"
          : "framework-ags-calendar"
      }
      anchor={
        Astal.WindowAnchor.TOP |
        Astal.WindowAnchor.BOTTOM |
        Astal.WindowAnchor.LEFT |
        Astal.WindowAnchor.RIGHT
      }
      layer={Astal.Layer.OVERLAY}
      exclusivity={Astal.Exclusivity.IGNORE}
      keymode={Astal.Keymode.ON_DEMAND}
      onKeyPressEvent={(_, event) => {
        if (event.get_keyval()[1] === Gdk.KEY_Escape) {
          close(mon);
          return true;
        }
        return false;
      }}
    >
      <overlay>
        <eventbox className="backdrop" onClick={() => close(mon)}>
          <box hexpand vexpand />
        </eventbox>
        <box
          className={
            kind === "calendar"
              ? "popup-anchor calendar-anchor"
              : "popup-anchor"
          }
          halign={Gtk.Align.END}
          valign={Gtk.Align.START}
        >
          {kind === "calendar" ? (
            <box className="control-panel calendar-panel">
              {new Gtk.Calendar({ visible: true })}
            </box>
          ) : (
            <ControlContents />
          )}
        </box>
      </overlay>
    </window>
  );
}
const tray = Tray.get_default();
const trayItems = Variable<string[]>(
  tray.get_items().map((item: any) => item.itemId),
);
tray.connect("item-added", (_: any, id: string) =>
  trayItems.set([...trayItems.get(), id]),
);
tray.connect("item-removed", (_: any, id: string) =>
  trayItems.set(trayItems.get().filter((key) => key !== id)),
);
function TrayItem({ id }: { id: string }) {
  const item = tray.get_item(id);
  if (!item) return <box />;
  const button = (
    <menubutton usePopover={false} tooltipText={item.title || "Tray item"}>
      <icon gicon={bind(item, "gicon")} css="font-size: 24px;" />
    </menubutton>
  ) as Gtk.MenuButton;
  // Menu buttons handle popup themselves; menu-less items need explicit activation.
  button.add_events(
    Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.SCROLL_MASK,
  );
  button.connect("button-press-event", (_self, event) => {
    if (item.menuModel) return false;
    const mouse = event.get_button()[1];
    if (mouse === 1) item.activate(0, 0);
    else if (mouse === 2 || mouse === 3) item.secondary_activate(0, 0);
    else return false;
    return true;
  });
  button.connect("scroll-event", (_self, event) => {
    const direction = event.get_scroll_direction()[1];
    if (direction === Gdk.ScrollDirection.UP) item.scroll(-1, "vertical");
    else if (direction === Gdk.ScrollDirection.DOWN) item.scroll(1, "vertical");
    else return false;
    return true;
  });
  function updateMenu() {
    button.menuModel = item.menuModel;
    button.sensitive = true;
    button.insert_action_group("dbusmenu", item.actionGroup);
  }
  updateMenu();
  const menuSignal = item.connect("notify::menu-model", updateMenu);
  const actionSignal = item.connect("notify::action-group", updateMenu);
  button.connect("destroy", () => {
    item.disconnect(menuSignal);
    item.disconnect(actionSignal);
  });
  return button;
}
function AppStrip({ mon }: { mon: Gdk.Monitor }) {
  return (
    <box className="app-strip" spacing={4}>
      {groupsState((snapshot) => {
        const index = App.get_monitors().indexOf(mon);
        const monitorName =
          Gdk.Screen.get_default()?.get_monitor_plug_name(index) ||
          mon.get_model() ||
          "";
        let groups: Group[] = [];
        try {
          groups = JSON.parse(snapshot || "[]");
        } catch {
          /* ignore invalid snapshot */
        }
        return groups
          .filter((group) => group.monitor === monitorName)
          .flatMap((group) =>
            group.workspaces.map((workspace) => (
              <box spacing={4}>
                <box className="island workspace-label">
                  <label label={workspace.label} />
                </box>
                {workspace.windows.map((window) => (
                  <button
                    className={
                      window.focused
                        ? "island app-button focused"
                        : "island app-button"
                    }
                    tooltipText={window.title}
                    onClicked={() => shell("focus-window", String(window.id))}
                  >
                    <box spacing={6}>
                      <Picture path={window.icon_path} size={24} />
                      {window.focused && (
                        <label
                          maxWidthChars={28}
                          ellipsize={3}
                          label={window.title}
                        />
                      )}
                    </box>
                  </button>
                ))}
              </box>
            )),
          );
      })}
    </box>
  );
}
function Bar(mon: Gdk.Monitor) {
  const batteryExpanded = Variable(false);
  const trayExpanded = Variable(false);
  return (
    <window
      name={`bar-${windowId++}`}
      onDestroy={() => {
        batteryExpanded.drop();
        trayExpanded.drop();
      }}
      className="bar-window"
      namespace="framework-ags-bar"
      gdkmonitor={mon}
      application={App}
      anchor={
        Astal.WindowAnchor.TOP |
        Astal.WindowAnchor.LEFT |
        Astal.WindowAnchor.RIGHT
      }
      exclusivity={Astal.Exclusivity.EXCLUSIVE}
      layer={Astal.Layer.TOP}
    >
      <centerbox className="bar" css="min-height: 32px; margin-top: 4px;">
        <AppStrip mon={mon} />
        <box className="island media" visible={state((s) => !!s.media_text)}>
          <label maxWidthChars={52} ellipsize={3} label={value("media_text")} />
        </box>
        <box className="bar-right" spacing={4} halign={Gtk.Align.END}>
          <box className="island perf" spacing={8}>
            {["cpu", "ram", "gpu"].map((key) => (
              <box vertical>
                <label className="secondary" label={key.toUpperCase()} />
                <label label={value(`perf_${key}`, "--")} />
              </box>
            ))}
            <box vertical>
              <label label={state((s) => `UP ${s.perf_up || "--"}/s`)} />
              <label label={state((s) => `DN ${s.perf_down || "--"}/s`)} />
            </box>
          </box>
          <eventbox
            className={value("battery_class", "island battery")}
            valign={Gtk.Align.FILL}
            onHover={() => batteryExpanded.set(true)}
            onHoverLost={() => batteryExpanded.set(false)}
          >
            <box className="battery-device">
              <box className="ring-slot" valign={Gtk.Align.CENTER} homogeneous>
                <circularprogress
                  className="battery-ring"
                  halign={Gtk.Align.CENTER}
                  valign={Gtk.Align.CENTER}
                  value={state((s) => Number(s.battery_value || 0) / 100)}
                  startAt={0.75}
                  endAt={0.75}
                >
                  <icon
                    className="battery-icon"
                    gicon={value("battery_icon", icon("batteryUnknown")).as(
                      (file) => Gio.FileIcon.new(Gio.File.new_for_path(file)),
                    )}
                    css="font-size: 20px;"
                  />
                </circularprogress>
              </box>
              <revealer
                className="battery-device-revealer"
                revealChild={batteryExpanded()}
                transitionType={Gtk.RevealerTransitionType.SLIDE_RIGHT}
                transitionDuration={120}
              >
                <label
                  className="battery-device-label"
                  label={value("battery_tooltip", "Battery --")}
                />
              </revealer>
            </box>
          </eventbox>
          <eventbox
            className="island tray"
            valign={Gtk.Align.FILL}
            onHover={() => trayExpanded.set(true)}
            onHoverLost={() => trayExpanded.set(false)}
          >
            <box className="tray-device">
              <box className="tray-slot" valign={Gtk.Align.CENTER} homogeneous>
                <Picture name="tray" />
              </box>
              <revealer
                className="tray-revealer"
                revealChild={trayExpanded()}
                transitionType={Gtk.RevealerTransitionType.SLIDE_RIGHT}
                transitionDuration={120}
              >
                <box className="tray-icons" spacing={2}>
                  {trayItems((ids) => ids.map((id) => <TrayItem id={id} />))}
                </box>
              </revealer>
            </box>
          </eventbox>
          <button
            className="island datetime"
            onClicked={() => toggle(mon, "calendar")}
          >
            <box vertical>
              <label label={value("datetime_date", "--/--")} />
              <label
                className="clock"
                label={value("datetime_time", "--:--")}
              />
            </box>
          </button>
          <button
            className="island control-button"
            onClicked={() => toggle(mon, "control")}
          >
            <box>
              <Picture name="controlCenter" size={23} />
              <label
                className="notification-badge"
                visible={state((s) => Number(s.notifications_count || 0) > 0)}
                label={value("notifications_label", "0")}
              />
            </box>
          </button>
        </box>
      </centerbox>
    </window>
  );
}
function mount(mon: Gdk.Monitor) {
  const bar = Bar(mon),
    control = Popup(mon, "control"),
    calendar = Popup(mon, "calendar");
  overlays.set(mon, { bar, control, calendar });
  control.hide();
  calendar.hide();
}

App.start({
  css: GLib.build_filenamev([directory, "style.css"]),
  main() {
    App.get_monitors().forEach(mount);
    App.connect("monitor-added", (_, mon) => mount(mon));
    App.connect("monitor-removed", (_, mon) => {
      const windows = overlays.get(mon);
      if (windows) {
        windows.bar.destroy();
        windows.control.destroy();
        windows.calendar.destroy();
        overlays.delete(mon);
      }
    });
    const daemon = subprocess(
      [config.stateBinary, "--config-file", config.stateConfig, "daemon"],
      patch,
      (error) => console.error("shell-state", error),
    );
    daemon.connect("exit", () => {
      console.error("shell-state daemon exited unexpectedly");
      System.exit(1);
    });
    for (const key of Object.keys(switches)) {
      refreshSwitch(key);
      GLib.timeout_add_seconds(
        GLib.PRIORITY_DEFAULT,
        key === "dnd" ? 4 : key === "lid" ? 10 : 6,
        () => {
          refreshSwitch(key);
          return GLib.SOURCE_CONTINUE;
        },
      );
    }
    GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 12, () => {
      if (view.get() === "wifi" && !wifiTarget.get()) scan();
      return GLib.SOURCE_CONTINUE;
    });
    // Home Manager restarts AGS after switching the prebuilt appearance CSS.
  },
});
