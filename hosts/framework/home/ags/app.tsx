import app from "ags/gtk4/app";
import { Astal, Gtk, Gdk } from "ags/gtk4";
import { createBinding, createState, createRoot, For, onCleanup } from "ags";
import { subprocess } from "ags/process";
import Tray from "gi://AstalTray";
import GLib from "gi://GLib";
import Gio from "gi://Gio";
import System from "system";
import ControlContents, {
  openView,
  resetControl,
  refreshWifi,
} from "./control-center";
import {
  initNotifications,
  NotificationPopups,
  unreadCount,
  unreadLabel,
} from "./notifications";
import {
  command,
  config,
  directory,
  state,
  groupsState,
  value,
  icon,
  patch,
  shell,
  switches,
  isLocalSwitch,
  refreshSwitch,
} from "./state";

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
const vertical = Gtk.Orientation.VERTICAL;

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
    <image
      gicon={
        file.startsWith("/")
          ? Gio.FileIcon.new(Gio.File.new_for_path(file))
          : Gio.ThemedIcon.new(file)
      }
      pixelSize={size}
    />
  );
}
function hover(widget: Gtk.Widget, enter: () => void, leave: () => void) {
  const motion = new Gtk.EventControllerMotion();
  motion.connect("enter", enter);
  motion.connect("leave", leave);
  widget.add_controller(motion);
}
function click(widget: Gtk.Widget, button: number, action: () => void) {
  const gesture = new Gtk.GestureClick({ button });
  gesture.connect("released", () => action());
  widget.add_controller(gesture);
}

type PopupKind = "control" | "calendar" | "power";
const [powerBusy, setPowerBusy] = createState(false);
const [powerError, setPowerError] = createState("");

function PowerContents() {
  return (
    <box class="control-panel power-panel" orientation={vertical} spacing={8}>
      <label class="cc-page-title" label="Power Mode" xalign={0} />
      <label
        class="secondary"
        label={value("battery_tooltip", "Battery --")}
        xalign={0}
      />
      {[
        ["performance", "Performance"],
        ["balanced", "Balanced"],
        ["power-saver", "Power Saver"],
      ].map(([profile, label]) => (
        <button
          class={value("battery_profile")((current) =>
            `power-option power-${profile}${current === label ? " selected" : ""}`,
          )}
          sensitive={powerBusy((busy) => !busy)}
          onClicked={() => {
            if (powerBusy()) return;
            setPowerBusy(true);
            setPowerError("");
            void command(
              [config.ccCmd, "power-profile", profile],
              patch,
              () =>
                setPowerError(
                  "Could not change power mode. Authorization may have been cancelled.",
                ),
            ).finally(() => setPowerBusy(false));
          }}
        >
          <box spacing={12}>
            <label label={label} hexpand xalign={0} />
            <label
              label={value("battery_profile")((current) =>
                current === label ? "✓" : "",
              )}
            />
          </box>
        </button>
      ))}
      <label
        class="secondary"
        label="Changing mode requires system authorization."
        wrap
        maxWidthChars={34}
        xalign={0}
      />
      <label visible={powerBusy} label="Applying…" xalign={0} />
      <label
        class="power-error"
        visible={powerError((error) => !!error)}
        label={powerError}
        wrap
        maxWidthChars={34}
        xalign={0}
      />
    </box>
  );
}

const overlays = new Map<
  Gdk.Monitor,
  {
    bar: Astal.Window;
    control: Astal.Window;
    calendar: Astal.Window;
    power: Astal.Window;
    dispose: (destroyWindows?: boolean) => void;
  }
>();
let windowId = 0;
function close(mon: Gdk.Monitor) {
  resetControl();
  const windows = overlays.get(mon);
  if (windows) {
    windows.control.visible = false;
    windows.calendar.visible = false;
    windows.power.visible = false;
  }
}
function toggle(mon: Gdk.Monitor, target: PopupKind) {
  const windows = overlays.get(mon);
  if (!windows) return;
  const wasVisible = windows[target].visible;
  // A single active panel avoids shared controls being edited on two monitors.
  for (const monitor of overlays.keys()) close(monitor);
  if (!wasVisible) {
    if (target === "control") openView("home");
    if (target === "power") {
      setPowerError("");
      void shell("refresh", "battery");
    }
    windows[target].visible = true;
    windows[target].present();
  }
}
function Popup(mon: Gdk.Monitor, kind: PopupKind) {
  const backdrop = (
    <box
      class="backdrop"
      hexpand
      vexpand
      $={(self) => click(self, 1, () => close(mon))}
    />
  );
  const content = (
    <box
      class={
        kind === "calendar" ? "popup-anchor calendar-anchor" : "popup-anchor"
      }
      halign={Gtk.Align.END}
      valign={Gtk.Align.START}
    >
      <scrolledwindow
        hscrollbarPolicy={Gtk.PolicyType.NEVER}
        propagateNaturalHeight
        maxContentHeight={createBinding(
          mon,
          "geometry",
        )((geometry) => Math.max(120, geometry.height - 80))}
      >
        {kind === "calendar" ? (
          <box class="control-panel calendar-panel">
            <Gtk.Calendar />
          </box>
        ) : kind === "power" ? (
          <PowerContents />
        ) : (
          <ControlContents />
        )}
      </scrolledwindow>
    </box>
  );
  const overlay = new Gtk.Overlay();
  overlay.set_child(backdrop);
  overlay.add_overlay(content);
  const window = (
    <window
      name={`${kind}-${windowId++}`}
      class="popup-window"
      application={app}
      gdkmonitor={mon}
      namespace={
        kind === "control"
          ? "framework-ags-control-center"
          : `framework-ags-${kind}`
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
      visible={false}
    >
      {overlay}
    </window>
  ) as Astal.Window;
  const keys = new Gtk.EventControllerKey();
  keys.connect("key-pressed", (_, key) => {
    if (key !== Gdk.KEY_Escape) return false;
    close(mon);
    return true;
  });
  window.add_controller(keys);
  return window;
}

function TrayItem({
  item,
  menuVisibility,
}: {
  item: any;
  menuVisibility: (open: boolean) => void;
}) {
  let popover: Gtk.PopoverMenu | null = null;
  let menuModel: Gio.MenuModel | null = null;
  let menuVisible = false;
  const setMenuVisible = (visible: boolean) => {
    if (visible !== menuVisible) {
      menuVisible = visible;
      menuVisibility(visible);
    }
  };
  const button = (
    <button
      class="tray-item"
      tooltipText={createBinding(
        item,
        "title",
      )((title) => title || "Tray item")}
      visible={createBinding(
        item,
        "status",
      )((status) => status !== Tray.Status.PASSIVE)}
    >
      <image gicon={createBinding(item, "gicon")} pixelSize={24} />
    </button>
  ) as Gtk.Button;
  function updateMenu() {
    button.insert_action_group("dbusmenu", item.actionGroup);
    const nextModel = item.menuModel;
    // Astal also notifies for edits inside the same GMenuModel. GTK observes
    // those edits itself; rebuilding here would close live/just-opened menus.
    if (nextModel === menuModel) return;
    menuModel = nextModel;
    if (popover && nextModel) {
      popover.set_menu_model(nextModel);
    } else if (popover) {
      popover.popdown();
      popover.unparent();
      popover = null;
      setMenuVisible(false);
    } else if (nextModel) {
      popover = Gtk.PopoverMenu.new_from_model(nextModel);
      popover.add_css_class("tray-menu");
      popover.set_has_arrow(false);
      popover.set_parent(button);
      popover.connect("notify::visible", () =>
        setMenuVisible(popover?.visible ?? false),
      );
    }
  }
  const menuRequest = new Gio.Cancellable();
  function openMenu() {
    if (!popover) {
      item.secondary_activate(0, 0);
      return;
    }
    // Request dynamic menu updates without blocking GTK on an unresponsive app.
    if (item.menuPath)
      Gio.DBus.session.call(
        item.itemId.split("/")[0],
        item.menuPath,
        "com.canonical.dbusmenu",
        "AboutToShow",
        new GLib.Variant("(i)", [0]),
        null,
        Gio.DBusCallFlags.NONE,
        1000,
        menuRequest,
        (connection, result) => {
          try {
            connection?.call_finish(result);
          } catch {
            /* optional menu update */
          }
        },
      );
    popover.popup();
  }
  button.connect("clicked", () => {
    if (item.isMenu && popover) openMenu();
    else item.activate(0, 0);
  });
  click(button, 2, () => item.secondary_activate(0, 0));
  click(button, 3, openMenu);
  const scroll = new Gtk.EventControllerScroll({
    flags:
      Gtk.EventControllerScrollFlags.BOTH_AXES |
      Gtk.EventControllerScrollFlags.DISCRETE,
  });
  scroll.connect("scroll", (_, dx, dy) => {
    if (dy) item.scroll(Math.round(dy), "vertical");
    else if (dx) item.scroll(Math.round(dx), "horizontal");
    return true;
  });
  button.add_controller(scroll);
  updateMenu();
  const menuSignal = item.connect("notify::menu-model", updateMenu);
  const actionSignal = item.connect("notify::action-group", () =>
    button.insert_action_group("dbusmenu", item.actionGroup),
  );
  onCleanup(() => {
    menuRequest.cancel();
    item.disconnect(menuSignal);
    item.disconnect(actionSignal);
    popover?.popdown();
    popover?.unparent();
    popover = null;
    setMenuVisible(false);
  });
  return button;
}

function AppStrip({ mon }: { mon: Gdk.Monitor }) {
  const groups = groupsState((snapshot) => {
    try {
      const parsed: Group[] = JSON.parse(snapshot);
      return parsed
        .filter((group) => group.monitor === mon.connector)
        .flatMap((group) => group.workspaces);
    } catch {
      return [];
    }
  });
  return (
    <box class="app-strip" spacing={4}>
      <For each={groups}>
        {(workspace) => (
          <box spacing={4}>
            <box class="island workspace-label">
              <label label={workspace.label} />
            </box>
            {workspace.windows.map((window) => (
              <button
                class={
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
        )}
      </For>
    </box>
  );
}

function BatteryRing() {
  const drawing = new Gtk.DrawingArea({
    content_width: 32,
    content_height: 32,
    halign: Gtk.Align.CENTER,
    valign: Gtk.Align.CENTER,
  });
  drawing.add_css_class("battery-ring");
  drawing.set_draw_func((widget, cr, width, height) => {
    const color = widget.get_color();
    const radius = Math.min(width, height) / 2 - 1.5;
    const progress = Math.max(
      0,
      Math.min(1, Number(state().battery_value || 0) / 100),
    );
    cr.setLineWidth(3);
    cr.setSourceRGBA(color.red, color.green, color.blue, 0.2);
    cr.arc(width / 2, height / 2, radius, 0, 2 * Math.PI);
    cr.stroke();
    if (progress > 0) {
      cr.setSourceRGBA(color.red, color.green, color.blue, color.alpha);
      cr.arc(
        width / 2,
        height / 2,
        radius,
        -Math.PI / 2,
        -Math.PI / 2 + progress * 2 * Math.PI,
      );
      cr.stroke();
    }
  });
  const unsubscribe = state.subscribe(() => drawing.queue_draw());
  onCleanup(unsubscribe);
  const overlay = new Gtk.Overlay();
  overlay.set_child(drawing);
  overlay.add_overlay(
    <image
      class="battery-icon"
      halign={Gtk.Align.CENTER}
      valign={Gtk.Align.CENTER}
      gicon={value(
        "battery_icon",
        icon("batteryUnknown"),
      )((file) => Gio.FileIcon.new(Gio.File.new_for_path(file)))}
      pixelSize={20}
    />,
  );
  return overlay;
}
function Bar(mon: Gdk.Monitor) {
  const [batteryExpanded, setBatteryExpanded] = createState(false);
  const [trayExpanded, setTrayExpanded] = createState(false);
  let trayHovered = false;
  let openMenus = 0;
  const tray = Tray.get_default();
  return (
    <window
      visible
      name={`bar-${windowId++}`}
      class="bar-window"
      namespace="framework-ags-bar"
      gdkmonitor={mon}
      application={app}
      anchor={
        Astal.WindowAnchor.TOP |
        Astal.WindowAnchor.LEFT |
        Astal.WindowAnchor.RIGHT
      }
      exclusivity={Astal.Exclusivity.EXCLUSIVE}
      layer={Astal.Layer.TOP}
    >
      <centerbox class="bar" css="min-height: 32px; margin-top: 4px;">
        <box $type="start">
          <AppStrip mon={mon} />
        </box>
        <box
          $type="center"
          class="island media"
          visible={state((s) => !!s.media_text)}
        >
          <label maxWidthChars={52} ellipsize={3} label={value("media_text")} />
        </box>
        <box $type="end" class="bar-right" spacing={4} halign={Gtk.Align.END}>
          <box class="island perf" spacing={8}>
            {["cpu", "ram", "gpu"].map((key) => (
              <box orientation={vertical}>
                <label class="secondary" label={key.toUpperCase()} />
                <label label={value(`perf_${key}`, "--")} />
              </box>
            ))}
            <box orientation={vertical}>
              <label label={state((s) => `UP ${s.perf_up || "--"}/s`)} />
              <label label={state((s) => `DN ${s.perf_down || "--"}/s`)} />
            </box>
          </box>
          <button
            class={value("battery_class", "island battery")}
            tooltipText="Power Mode"
            onClicked={() => toggle(mon, "power")}
            valign={Gtk.Align.FILL}
            $={(self) =>
              hover(
                self,
                () => setBatteryExpanded(true),
                () => setBatteryExpanded(false),
              )
            }
          >
            <box class="battery-device">
              <box class="ring-slot" valign={Gtk.Align.CENTER} homogeneous>
                <BatteryRing />
              </box>
              <revealer
                class="battery-device-revealer"
                revealChild={batteryExpanded}
                transitionType={Gtk.RevealerTransitionType.SLIDE_RIGHT}
                transitionDuration={120}
              >
                <label
                  class="battery-device-label"
                  label={value("battery_tooltip", "Battery --")}
                />
              </revealer>
            </box>
          </button>
          <box
            class="island tray"
            valign={Gtk.Align.FILL}
            $={(self) =>
              hover(
                self,
                () => {
                  trayHovered = true;
                  setTrayExpanded(true);
                },
                () => {
                  trayHovered = false;
                  setTrayExpanded(openMenus > 0);
                },
              )
            }
          >
            <box class="tray-device">
              <box class="tray-slot" valign={Gtk.Align.CENTER} homogeneous>
                <Picture name="tray" />
              </box>
              <revealer
                class="tray-revealer"
                revealChild={trayExpanded}
                transitionType={Gtk.RevealerTransitionType.SLIDE_RIGHT}
                transitionDuration={120}
              >
                <box class="tray-icons" spacing={2}>
                  <For each={createBinding(tray, "items")}>
                    {(item) => (
                      <TrayItem
                        item={item}
                        menuVisibility={(open) => {
                          openMenus = Math.max(0, openMenus + (open ? 1 : -1));
                          setTrayExpanded(trayHovered || openMenus > 0);
                        }}
                      />
                    )}
                  </For>
                </box>
              </revealer>
            </box>
          </box>
          <button
            class="island datetime"
            onClicked={() => toggle(mon, "calendar")}
          >
            <box orientation={vertical}>
              <label label={value("datetime_date", "--/--")} />
              <label class="clock" label={value("datetime_time", "--:--")} />
            </box>
          </button>
          <button
            class="island control-button"
            onClicked={() => toggle(mon, "control")}
          >
            <box>
              <Picture name="controlCenter" size={23} />
              <label
                class="notification-badge"
                visible={unreadCount((count) => count > 0)}
                label={unreadLabel}
              />
            </box>
          </button>
        </box>
      </centerbox>
    </window>
  );
}
function mount(mon: Gdk.Monitor) {
  createRoot((dispose) => {
    const bar = Bar(mon),
      control = Popup(mon, "control"),
      calendar = Popup(mon, "calendar"),
      power = Popup(mon, "power");
    overlays.set(mon, {
      bar,
      control,
      calendar,
      power,
      dispose(destroyWindows = true) {
        dispose();
        if (destroyWindows) {
          bar.destroy();
          control.destroy();
          calendar.destroy();
          power.destroy();
        }
      },
    });
  });
}
function syncMonitors() {
  const monitors = app.get_monitors();
  for (const [mon, windows] of overlays) {
    if (!monitors.includes(mon)) {
      close(mon);
      windows.dispose();
      overlays.delete(mon);
    }
  }
  for (const mon of monitors) if (!overlays.has(mon)) mount(mon);
}

app.start({
  css: GLib.build_filenamev([directory, "style.css"]),
  main() {
    // Claim the notification bus name before the bars subscribe to its state.
    onCleanup(initNotifications());
    NotificationPopups();
    syncMonitors();
    const monitorSignal = app.connect("notify::monitors", syncMonitors);
    onCleanup(() => {
      app.disconnect(monitorSignal);
      // Do not tear down layer-shell native surfaces inside application shutdown;
      // GTK is already shutting down its backend. Explicit destruction is for hotplug.
      for (const windows of overlays.values()) windows.dispose(false);
      overlays.clear();
    });
    const daemon = subprocess(
      [config.stateBinary, "--config-file", config.stateConfig, "daemon"],
      patch,
      () => console.error("shell-state stderr"),
    );
    const exitSignal = daemon.connect("exit", () => {
      console.error("shell-state daemon exited unexpectedly");
      System.exit(1);
    });
    onCleanup(() => {
      daemon.disconnect(exitSignal);
      daemon.kill();
    });
    const polled = Object.keys(switches).filter((key) => !isLocalSwitch(key));
    const timers = polled.map((key) => {
      void refreshSwitch(key);
      return GLib.timeout_add_seconds(
        GLib.PRIORITY_DEFAULT,
        key === "lid" ? 10 : 6,
        () => {
          void refreshSwitch(key);
          return GLib.SOURCE_CONTINUE;
        },
      );
    });
    timers.push(
      GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 12, () => {
        refreshWifi();
        return GLib.SOURCE_CONTINUE;
      }),
    );
    onCleanup(() => timers.forEach((timer) => GLib.source_remove(timer)));
  },
});
