// Injected only into the private smoke copy; never included by the production app.
import { notifications } from "./notifications";
import { switches, toggleSwitch } from "./state";

export async function runSmoke({
  app,
  Gtk,
  Gdk,
  GLib,
  Gio,
  overlays,
  toggle,
  close,
  openView,
  mount,
}) {
  const assert = (condition, message) => {
    if (!condition) throw Error(`SMOKE_ASSERT ${message}`);
  };
  const delay = (ms = 180) =>
    new Promise<void>((resolve) => {
      GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
        resolve();
        return GLib.SOURCE_REMOVE;
      });
    });
  const children = (widget) => {
    const result = [];
    for (
      let child = widget.get_first_child();
      child;
      child = child.get_next_sibling()
    )
      result.push(child);
    return result;
  };
  const all = (widget, predicate) => [
    ...(predicate(widget) ? [widget] : []),
    ...children(widget).flatMap((child) => all(child, predicate)),
  ];
  const find = (widget, name) => all(widget, (w) => w.has_css_class(name))[0];
  const controllers = (widget, type) => {
    const model = widget.observe_controllers();
    return Array.from({ length: model.get_n_items() }, (_, i) =>
      model.get_item(i),
    ).filter((c) => c instanceof type);
  };
  const hover = (widget, enter) => {
    const motion = controllers(widget, Gtk.EventControllerMotion)[0];
    assert(motion, "missing hover controller");
    if (enter) motion.emit("enter", 0, 0);
    else motion.emit("leave");
  };
  const callFixture = (method) =>
    new Promise<void>((resolve, reject) => {
      Gio.DBus.session.call(
        "dev.framework.SmokeTray",
        "/Smoke",
        "dev.framework.Smoke",
        method,
        null,
        null,
        Gio.DBusCallFlags.NONE,
        2000,
        null,
        (connection, result) => {
          try {
            connection.call_finish(result);
            resolve();
          } catch (error) {
            reject(error);
          }
        },
      );
    });

  try {
    await delay(700);
    const monitors = app.get_monitors();
    print(`SMOKE_MONITORS count=${monitors.length}`);
    assert(monitors.length === 2, "expected two monitors");
    const first = monitors[0];
    const bars = app
      .get_windows()
      .filter((window) => window.name.startsWith("bar-"));
    assert(bars.length === 2, `expected two bars, got ${bars.length}`);
    const widgets = bars.map((bar) => {
      const battery = find(bar, "battery");
      const tray = find(bar, "tray");
      const ring = find(bar, "battery-ring");
      const ringSlot = find(bar, "ring-slot");
      const traySlot = find(bar, "tray-slot");
      const batteryReveal = find(bar, "battery-device-revealer");
      const trayReveal = find(bar, "tray-revealer");
      const peers = [
        find(bar, "perf"),
        find(bar, "datetime"),
        find(bar, "control-button"),
      ];
      assert(
        [
          battery,
          tray,
          ring,
          ringSlot,
          traySlot,
          batteryReveal,
          trayReveal,
          ...peers,
        ].every(Boolean),
        "missing bar widget",
      );
      const heights = [battery, tray, ...peers].map((widget) =>
        widget.get_allocated_height(),
      );
      assert(
        heights.every((h) => h === heights[0]),
        `outer widget heights differ: ${heights}`,
      );
      assert(
        ring.get_allocated_width() === 32 && ring.get_allocated_height() === 32,
        "battery ring must be 32x32",
      );
      for (const slot of [ringSlot, traySlot])
        assert(
          slot.get_allocated_width() === 40 &&
            slot.get_allocated_height() === 32,
          "battery/tray slot must be 40x32",
        );
      return { battery, tray, batteryReveal, trayReveal };
    });
    for (const type of ["battery", "tray"]) {
      const reveal = `${type}Reveal`;
      assert(
        widgets.every((widget) => !widget[reveal].revealChild),
        `${type} initially revealed`,
      );
      hover(widgets[0][type], true);
      await delay();
      assert(
        widgets[0][reveal].revealChild && !widgets[1][reveal].revealChild,
        `${type} hover leaked between monitors`,
      );
      hover(widgets[0][type], false);
      await delay();
      assert(
        widgets.every((widget) => !widget[reveal].revealChild),
        `${type} stayed revealed after leave`,
      );
      print(`SMOKE_WIDGET_${type.toUpperCase()}_PASS`);
    }

    toggle(first, "control");
    await delay();
    const panel = overlays.get(first).control;
    const rows = all(panel, (w) => w.has_css_class("cc-slider-row"));
    assert(
      rows.length === 2,
      `expected home volume/brightness rows, got ${rows.length}`,
    );
    const positions = rows.map((row) => {
      const slot = find(row, "slider-icon");
      const image = all(slot, (w) => w instanceof Gtk.Image)[0];
      const scale = find(row, "cc-scale");
      assert(
        slot.get_allocated_width() === 40 && slot.get_allocated_height() === 40,
        `slider slot must be 40x40: ${slot.get_allocated_width()}x${slot.get_allocated_height()}`,
      );
      assert(image.get_pixel_size() === 22, "slider icons must both be 22px");
      const [valid, x, y] = image.translate_coordinates(panel, 0, 0);
      const [rowValid, , rowY] = row.translate_coordinates(panel, 0, 0);
      const [scaleValid, scaleX] = scale.translate_coordinates(panel, 0, 0);
      assert(valid && rowValid && scaleValid, "unable to locate slider icon");
      assert(
        Math.abs(
          y +
            image.get_allocated_height() / 2 -
            rowY -
            row.get_allocated_height() / 2,
        ) <= 1,
        "slider icon is not vertically centered",
      );
      return { centerX: x + image.get_allocated_width() / 2, scaleX };
    });
    assert(
      positions[0].centerX === positions[1].centerX &&
        positions[0].scaleX === positions[1].scaleX,
      "slider icons/tracks are not aligned",
    );
    print("SMOKE_SLIDER_ALIGNMENT_PASS");
    const actionLog = `${GLib.getenv("work")}/actions.log`;
    const readActions = () => {
      const file = Gio.File.new_for_path(actionLog);
      if (!file.query_exists(null)) return "";
      const [, contents] = file.load_contents(null);
      return new TextDecoder().decode(contents);
    };
    const volume = find(rows[0], "cc-scale");
    const brightness = find(rows[1], "cc-scale");
    const beforeActions = readActions();
    volume.set_value(0.42);
    brightness.set_value(0.55);
    await delay();
    assert(
      readActions() === beforeActions,
      "programmatic slider update issued a system action",
    );
    volume.emit("change-value", Gtk.ScrollType.JUMP, 0.37);
    brightness.emit("change-value", Gtk.ScrollType.JUMP, 0.61);
    await delay();
    assert(
      readActions().includes("audio set speaker 37"),
      "volume did not use proposed user value",
    );
    assert(
      readActions().includes("brightness set 61"),
      "brightness did not use proposed user value",
    );
    assert(
      Math.abs(volume.get_value() - 0.37) < 0.000001 &&
        Math.abs(brightness.get_value() - 0.61) < 0.000001,
      "slider handlers prevented GTK default adjustment",
    );
    print("SMOKE_SLIDER_ACTIONS_PASS");
    const grim = GLib.getenv("SMOKE_GRIM");
    if (grim) {
      const screenshot = Gio.Subprocess.new(
        [
          grim,
          "-o",
          first.get_connector(),
          `${GLib.getenv("work")}/control-home.png`,
        ],
        Gio.SubprocessFlags.NONE,
      );
      await new Promise<void>((resolve, reject) =>
        screenshot.wait_check_async(null, (process, result) => {
          try {
            process.wait_check_finish(result);
            resolve();
          } catch (error) {
            reject(error);
          }
        }),
      );
    }
    for (const name of ["wifi", "sound", "notifications", "session", "home"]) {
      openView(name);
      await delay();
      if (name === "wifi") {
        const locked = all(panel, (w) => w.has_css_class("wifi-row")).find(
          (row) =>
            all(row, (w) => w instanceof Gtk.Label).some(
              (label) => label.get_label() === "Locked",
            ),
        );
        assert(locked, "missing secure Wi-Fi fixture row");
        locked.emit("clicked");
        await delay();
        const password = all(panel, (w) => w instanceof Gtk.Entry)[0];
        assert(
          password && !password.get_visibility(),
          "Wi-Fi password field is not masked",
        );
        password.set_text("smoke-private-password");
        password.emit("activate");
        await delay(300);
        assert(
          !find(panel, "wifi-password"),
          "submitted Wi-Fi password was not cleared",
        );
        assert(
          all(panel, (w) => w instanceof Gtk.Label).some((w) =>
            w.get_label().includes("Wi-Fi operation failed"),
          ),
          "Wi-Fi failure is not visible",
        );
        print("SMOKE_WIFI_PASS");
      }
      if (name === "session") {
        const labels = all(panel, (w) => w instanceof Gtk.Label).map((w) =>
          w.get_label(),
        );
        assert(
          ["Lock", "Hibernate", "Log Out", "Restart", "Shut Down"].every(
            (label) => labels.includes(label),
          ),
          "missing session action",
        );
      }
      print(`SMOKE_VIEW ${name}`);
    }
    const keys = controllers(panel, Gtk.EventControllerKey)[0];
    assert(keys, "missing Escape controller");
    keys.emit("key-pressed", Gdk.KEY_Escape, 0, 0);
    assert(!panel.visible, "Escape did not dismiss control center");
    toggle(first, "calendar");
    await delay();
    const calendar = overlays.get(first).calendar;
    const backdrop = find(calendar, "backdrop");
    const outsideClick = controllers(backdrop, Gtk.GestureClick).find(
      (c) => c.get_button() === 1,
    );
    assert(outsideClick, "missing backdrop click controller");
    outsideClick.emit("released", 1, 0, 0);
    assert(!calendar.visible, "backdrop click did not dismiss calendar");
    print("SMOKE_WIDGET_PASS");

    // Real Notify calls on the private bus exercise AstalNotifd ownership.
    const notify = (summary, actions = [], hints = {}) =>
      new Promise<number>((resolve, reject) => {
        Gio.DBus.session.call(
          "org.freedesktop.Notifications",
          "/org/freedesktop/Notifications",
          "org.freedesktop.Notifications",
          "Notify",
          new GLib.Variant("(susssasa{sv}i)", [
            "Smoke",
            0,
            "",
            summary,
            "Body with <b>markup</b> & <a href='https://x'>link</a>",
            actions,
            hints,
            -1,
          ]),
          new GLib.VariantType("(u)"),
          Gio.DBusCallFlags.NONE,
          2000,
          null,
          (connection, result) => {
            try {
              resolve(connection.call_finish(result).deep_unpack()[0]);
            } catch (error) {
              reject(error);
            }
          },
        );
      });
    const popupWindow = app
      .get_windows()
      .find((w) => w.name === "notification-popups");
    assert(popupWindow, "missing notification popup window");
    assert(!popupWindow.visible, "popup window visible without notifications");
    const cards = (widget) =>
      all(widget, (w) => w.has_css_class("notification-card"));
    const badge = find(bars[0], "notification-badge");
    await notify("Smoke one", ["default", "Open", "reply", "Reply"]);
    await notify("Smoke two");
    await delay(300);
    assert(popupWindow.visible, "notification popup did not appear");
    assert(cards(popupWindow).length === 2, "expected two popup cards");
    assert(
      badge.visible && badge.get_label() === "2",
      `unread badge mismatch: ${badge.get_label()}`,
    );
    assert(notifications().length === 2, "center did not record both");
    const tallHeight = popupWindow.get_height();
    const reply = all(popupWindow, (w) => w instanceof Gtk.Button).find((b) =>
      all(b, (w) => w instanceof Gtk.Label).some(
        (l) => l.get_label() === "Reply",
      ),
    );
    assert(reply, "notification action button missing");
    reply.emit("clicked");
    await delay(300);
    assert(notifications().length === 1, "invoked action did not resolve");
    assert(cards(popupWindow).length === 1, "invoked popup remained");
    assert(badge.get_label() === "1", "invoked notification stayed unread");
    assert(
      popupWindow.get_height() < tallHeight,
      `popup surface did not shrink: ${tallHeight} -> ${popupWindow.get_height()}`,
    );
    toggle(first, "control");
    openView("notifications");
    await delay();
    assert(!badge.visible, "opening notifications did not mark them read");
    assert(cards(panel).length === 1, "center card missing");
    toggleSwitch("dnd");
    await delay();
    assert(switches.dnd() === "on", "DND toggle did not reach AstalNotifd");
    await notify("Smoke quiet");
    await delay(300);
    assert(notifications().length === 2, "DND dropped a notification");
    assert(
      cards(popupWindow).length === 0 && !popupWindow.visible,
      "DND still showed a popup",
    );
    assert(badge.get_label() === "1", "DND notification was not unread");
    toggleSwitch("dnd");
    const clear = all(panel, (w) => w.has_css_class("cc-action")).find(
      (b) => b.get_tooltip_text() === "Clear",
    );
    assert(clear, "missing clear-notifications action");
    clear.emit("clicked");
    await delay(300);
    assert(notifications().length === 0, "clear did not dismiss all");
    assert(cards(panel).length === 0, "cleared center cards remain");
    assert(!badge.visible, "badge remained after clearing");
    close(first);
    print("SMOKE_NOTIFICATIONS_PASS");

    hover(widgets[0].tray, true);
    await delay(400);
    const buttons = all(bars[0], (w) => w.has_css_class("tray-item"));
    assert(
      buttons.length === 2,
      `expected two fixture tray items, got ${buttons.length}`,
    );
    const menuButton = buttons.find((w) =>
      w.get_tooltip_text()?.includes("MenuItem"),
    );
    const activeButton = buttons.find((w) =>
      w.get_tooltip_text()?.includes("ActiveItem"),
    );
    assert(menuButton && activeButton, "fixture tray tooltips unavailable");
    activeButton.emit("clicked");
    const secondary = controllers(activeButton, Gtk.GestureClick).find(
      (c) => c.get_button() === 2,
    );
    assert(secondary, "missing secondary-click controller");
    secondary.emit("released", 1, 0, 0);
    const scroll = controllers(activeButton, Gtk.EventControllerScroll)[0];
    assert(scroll, "missing tray scroll controller");
    scroll.emit("scroll", 0, 1);
    scroll.emit("scroll", -1, 0);
    const context = controllers(activeButton, Gtk.GestureClick).find(
      (c) => c.get_button() === 3,
    );
    assert(context, "missing context-menu controller");
    context.emit("released", 1, 0, 0);
    await delay();
    const activePopup = all(
      activeButton,
      (w) => w instanceof Gtk.PopoverMenu,
    )[0];
    assert(activePopup?.get_visible(), "right-click DBusMenu did not open");
    activePopup.popdown();
    await delay();
    menuButton.emit("clicked");
    await delay(300);
    const popup = all(menuButton, (w) => w instanceof Gtk.PopoverMenu)[0];
    assert(
      popup?.get_visible(),
      "DBusMenu did not remain open after async layout update",
    );
    assert(
      all(popup, (w) => w instanceof Gtk.Label).some(
        (w) => w.get_label() === "Updated smoke action",
      ),
      "DBusMenu did not apply dynamic layout contents",
    );
    print("SMOKE_TRAY_DYNAMIC_PASS");
    hover(widgets[0].tray, false);
    await delay();
    assert(
      widgets[0].trayReveal.revealChild,
      "tray collapsed while its menu is open",
    );
    // GtkModelButton is private in GTK4; its public Widget activation is supported.
    const actions = all(popup, (w) => w.get_css_name() === "modelbutton");
    assert(actions.length > 0, "DBusMenu has no action");
    assert(actions[0].activate(), "DBusMenu action could not be activated");
    await delay();
    popup.popdown();
    await delay(300);
    await callFixture("Remove");
    await delay(400);
    assert(
      bars.every(
        (bar) => all(bar, (w) => w.has_css_class("tray-item")).length === 0,
      ),
      "removed tray items remain attached",
    );
    print("SMOKE_TRAY_PASS");
    // Exercise the same owned-window lifecycle as removal/reconnection, without
    // changing the compositor or the user's physical output configuration.
    overlays.get(first).dispose();
    overlays.delete(first);
    await delay();
    assert(
      app.get_windows().filter((w) => w.name.startsWith("bar-")).length === 1,
      "monitor disposal left a bar attached",
    );
    mount(first);
    await delay();
    assert(
      app.get_windows().filter((w) => w.name.startsWith("bar-")).length === 2,
      "monitor remount did not recreate its bar",
    );
    print("SMOKE_LIFECYCLE_PASS");
    print("SMOKE_PASS");
    app.quit();
  } catch (error) {
    console.error(error);
    print("SMOKE_FAIL");
    app.quit();
  }
}
