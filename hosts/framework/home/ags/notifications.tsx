import app from "ags/gtk4/app";
import { Astal, Gtk, Gdk } from "ags/gtk4";
import { Accessor, createState, For } from "ags";
import Notifd from "gi://AstalNotifd";
import GLib from "gi://GLib";
import Gio from "gi://Gio";
import Pango from "gi://Pango";
import { icon, localSwitch, setSwitch } from "./state";

type Item = Notifd.Notification;

// Popups hide after this delay; the entry stays in the center until dismissed.
const POPUP_TIMEOUT_MS = 7000;
const POPUP_LIMIT = 4;
const HISTORY_LIMIT = 50;
const vertical = Gtk.Orientation.VERTICAL;

const [items, setItems] = createState<Item[]>([]);
const [popups, setPopups] = createState<Item[]>([]);
const [unread, setUnread] = createState<number[]>([]);
export const notifications: Accessor<Item[]> = items;
export const unreadCount = unread((ids) => ids.length);
export const unreadLabel = unread((ids) =>
  ids.length > 99 ? "99+" : String(ids.length),
);

let notifd: Notifd.Notifd | null = null;
const popupTimers = new Map<number, number>();

const newestFirst = (list: Item[]) =>
  [...list].sort((a, b) => b.time - a.time || b.id - a.id);

function sync() {
  if (notifd) setItems(newestFirst(notifd.notifications));
}
function clearTimer(id: number) {
  const timer = popupTimers.get(id);
  if (timer !== undefined) GLib.source_remove(timer);
  popupTimers.delete(id);
}
function hidePopup(id: number) {
  clearTimer(id);
  setPopups((list) => list.filter((n) => n.id !== id));
}
function hideAllPopups() {
  for (const id of popupTimers.keys()) clearTimer(id);
  setPopups([]);
}
function showPopup(n: Item) {
  clearTimer(n.id);
  const next = [n, ...popups().filter((p) => p.id !== n.id)];
  for (const dropped of next.slice(POPUP_LIMIT)) clearTimer(dropped.id);
  setPopups(next.slice(0, POPUP_LIMIT));
  if (n.urgency !== Notifd.Urgency.CRITICAL)
    popupTimers.set(
      n.id,
      GLib.timeout_add(GLib.PRIORITY_DEFAULT, POPUP_TIMEOUT_MS, () => {
        popupTimers.delete(n.id);
        setPopups((list) => list.filter((p) => p.id !== n.id));
        return GLib.SOURCE_REMOVE;
      }),
    );
}
export function markRead(id: number) {
  setUnread((ids) => ids.filter((unreadId) => unreadId !== id));
}
export function markAllRead() {
  setUnread([]);
}
export function dismiss(n: Item) {
  markRead(n.id);
  hidePopup(n.id);
  n.dismiss();
}
export function dismissAll() {
  for (const n of items()) dismiss(n);
}
function invoke(n: Item, actionId: string) {
  markRead(n.id);
  hidePopup(n.id);
  n.invoke(actionId);
}
function trimHistory() {
  for (const n of items().slice(HISTORY_LIMIT)) dismiss(n);
}

/** Owns org.freedesktop.Notifications; call once inside app.start(). */
export function initNotifications() {
  const daemon = Notifd.get_default();
  notifd = daemon;
  // The daemon must not expire entries: popup timeouts are handled by the UI.
  // Apps can still close their own notifications through CloseNotification.
  if (!daemon.ignoreTimeout) daemon.ignoreTimeout = true;
  if (daemon.defaultTimeout !== -1) daemon.defaultTimeout = -1;
  const syncDnd = () => {
    setSwitch("dnd", daemon.dontDisturb ? "on" : "off");
    if (daemon.dontDisturb) hideAllPopups();
  };
  localSwitch("dnd", () => {
    daemon.dontDisturb = !daemon.dontDisturb;
  });
  syncDnd();
  sync();
  const signals = [
    daemon.connect("notify::dont-disturb", syncDnd),
    daemon.connect("notified", (_, id: number) => {
      sync();
      const n = daemon.get_notification(id);
      if (!n) return;
      setUnread((ids) => [...ids.filter((unreadId) => unreadId !== id), id]);
      if (!daemon.dontDisturb) showPopup(n);
      // Trim after the signal returns: dismissal re-enters the daemon.
      GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
        trimHistory();
        return GLib.SOURCE_REMOVE;
      });
    }),
    daemon.connect("resolved", (_, id: number) => {
      markRead(id);
      hidePopup(id);
      sync();
    }),
  ];
  return () => {
    signals.forEach((signal) => daemon.disconnect(signal));
    hideAllPopups();
  };
}

function fileIcon(value: string) {
  if (!value) return null;
  const file = value.startsWith("file://")
    ? Gio.File.new_for_uri(value)
    : value.startsWith("/")
      ? Gio.File.new_for_path(value)
      : null;
  return file?.query_exists(null) ? Gio.FileIcon.new(file) : null;
}
function themedIcon(value: string) {
  const display = Gdk.Display.get_default();
  if (!value || !display) return null;
  return Gtk.IconTheme.get_for_display(display).has_icon(value)
    ? Gio.ThemedIcon.new(value)
    : null;
}
function appIcon(n: Item) {
  return (
    themedIcon(n.appIcon) ||
    fileIcon(n.appIcon) ||
    themedIcon(n.desktopEntry) ||
    Gio.FileIcon.new(Gio.File.new_for_path(icon("notification")))
  );
}
function bodyMarkup(body: string) {
  // Keep Pango-compatible markup; drop links/images and escape anything invalid.
  const text = body
    .replace(/<a\b[^>]*>(.*?)<\/a>/gis, "$1")
    .replace(/<img\b[^>]*>/gi, "")
    .trim();
  try {
    Pango.parse_markup(text, -1, "\0");
    return text;
  } catch {
    return GLib.markup_escape_text(text.replace(/<[^>]*>/g, ""), -1);
  }
}
function clock(time: number) {
  return GLib.DateTime.new_from_unix_local(time)?.format("%H:%M") ?? "";
}

export function NotificationCard({
  n,
  mode,
}: {
  n: Item;
  mode: "popup" | "center";
}) {
  const [expanded, setExpanded] = createState(false);
  const image = fileIcon(n.image);
  const actions = n.actions.filter((action) => action.id !== "default");
  const hasDefault = n.actions.some((action) => action.id === "default");
  const classes = [
    "notification-card",
    mode,
    n.urgency === Notifd.Urgency.CRITICAL
      ? "critical"
      : n.urgency === Notifd.Urgency.LOW
        ? "low"
        : "normal",
  ];
  const card = (
    <box
      cssClasses={
        mode === "center"
          ? unread((ids) => [
              ...classes,
              ...(ids.includes(n.id) ? ["unread"] : []),
            ])
          : classes
      }
      orientation={vertical}
      spacing={8}
    >
      <box cssClasses={["notification-header"]} spacing={8}>
        <image gicon={appIcon(n)} pixelSize={16} />
        <label
          cssClasses={["secondary"]}
          hexpand
          xalign={0}
          maxWidthChars={24}
          ellipsize={Pango.EllipsizeMode.END}
          label={n.appName || n.desktopEntry || "Notification"}
        />
        <label
          cssClasses={["unread-dot"]}
          visible={
            mode === "center" ? unread((ids) => ids.includes(n.id)) : false
          }
          label="●"
        />
        <label cssClasses={["secondary"]} label={clock(n.time)} />
        <button
          cssClasses={["notification-close"]}
          tooltipText="Dismiss"
          onClicked={() => dismiss(n)}
        >
          <image iconName="window-close-symbolic" pixelSize={14} />
        </button>
      </box>
      <box spacing={10}>
        {image && (
          <image
            cssClasses={["notification-image"]}
            gicon={image}
            pixelSize={48}
            valign={Gtk.Align.START}
          />
        )}
        <box orientation={vertical} hexpand spacing={4}>
          <label
            cssClasses={["heading"]}
            xalign={0}
            wrap
            wrapMode={Pango.WrapMode.WORD_CHAR}
            maxWidthChars={34}
            lines={2}
            ellipsize={Pango.EllipsizeMode.END}
            label={n.summary || n.appName || "Notification"}
          />
          <label
            cssClasses={["notification-body"]}
            visible={!!n.body.trim()}
            xalign={0}
            wrap
            wrapMode={Pango.WrapMode.WORD_CHAR}
            maxWidthChars={40}
            useMarkup
            lines={mode === "popup" ? 4 : expanded((open) => (open ? -1 : 3))}
            ellipsize={Pango.EllipsizeMode.END}
            label={bodyMarkup(n.body)}
          />
        </box>
      </box>
      {actions.length > 0 && (
        <box cssClasses={["notification-actions"]} homogeneous spacing={6}>
          {actions.map((action) => (
            <button onClicked={() => invoke(n, action.id)}>
              <label
                label={action.label || action.id}
                ellipsize={Pango.EllipsizeMode.END}
              />
            </button>
          ))}
        </box>
      )}
    </box>
  ) as Gtk.Box;
  const primary = new Gtk.GestureClick({ button: Gdk.BUTTON_PRIMARY });
  primary.connect("released", () => {
    if (mode === "center") {
      markRead(n.id);
      setExpanded(!expanded());
    } else if (hasDefault) invoke(n, "default");
    else {
      markRead(n.id);
      hidePopup(n.id);
    }
  });
  card.add_controller(primary);
  const secondary = new Gtk.GestureClick({ button: Gdk.BUTTON_SECONDARY });
  secondary.connect("released", () => dismiss(n));
  card.add_controller(secondary);
  return card;
}

/** One layer surface; with no fixed output, Niri places it on the focused one. */
export function NotificationPopups() {
  const win = (
    <window
      name="notification-popups"
      namespace="framework-ags-notifications"
      class="notification-popup-window"
      application={app}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.RIGHT}
      layer={Astal.Layer.OVERLAY}
      exclusivity={Astal.Exclusivity.NORMAL}
      keymode={Astal.Keymode.NONE}
      visible={popups((list) => list.length > 0)}
    >
      <box
        cssClasses={["notification-popups"]}
        orientation={vertical}
        spacing={8}
      >
        <For each={popups}>
          {(n) => <NotificationCard n={n} mode="popup" />}
        </For>
      </box>
    </window>
  ) as Astal.Window;
  // GTK keeps the largest size; reset it so removed cards stop blocking input.
  popups.subscribe(() => win.set_default_size(-1, -1));
  return win;
}
