// Private smoke-test fixture only: never run on the desktop's session bus.
import Gio from "gi://Gio";
import GLib from "gi://GLib";

if (GLib.getenv("FRAMEWORK_AGS_SMOKE") !== "1")
  throw Error("The tray fixture requires the isolated smoke-test harness");

const itemXml = `<node><interface name="org.kde.StatusNotifierItem">
  <property name="Category" type="s" access="read"/>
  <property name="Id" type="s" access="read"/>
  <property name="Title" type="s" access="read"/>
  <property name="Status" type="s" access="read"/>
  <property name="WindowId" type="u" access="read"/>
  <property name="IconName" type="s" access="read"/>
  <property name="IconPixmap" type="a(iiay)" access="read"/>
  <property name="OverlayIconName" type="s" access="read"/>
  <property name="OverlayIconPixmap" type="a(iiay)" access="read"/>
  <property name="AttentionIconName" type="s" access="read"/>
  <property name="AttentionIconPixmap" type="a(iiay)" access="read"/>
  <property name="AttentionMovieName" type="s" access="read"/>
  <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
  <property name="ItemIsMenu" type="b" access="read"/>
  <property name="Menu" type="o" access="read"/>
  <method name="Activate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
  <method name="SecondaryActivate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
  <method name="ContextMenu"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
  <method name="Scroll"><arg type="i" direction="in"/><arg type="s" direction="in"/></method>
  <signal name="NewIcon"/><signal name="NewToolTip"/>
</interface></node>`;
const menuXml = `<node><interface name="com.canonical.dbusmenu">
  <property name="Version" type="u" access="read"/>
  <property name="TextDirection" type="s" access="read"/>
  <property name="Status" type="s" access="read"/>
  <property name="IconThemePath" type="as" access="read"/>
  <method name="GetLayout"><arg type="i" direction="in"/><arg type="i" direction="in"/><arg type="as" direction="in"/><arg type="u" direction="out"/><arg type="(ia{sv}av)" direction="out"/></method>
  <method name="GetGroupProperties"><arg type="ai" direction="in"/><arg type="as" direction="in"/><arg type="a(ia{sv})" direction="out"/></method>
  <method name="GetProperty"><arg type="i" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="out"/></method>
  <method name="Event"><arg type="i" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="in"/><arg type="u" direction="in"/></method>
  <method name="EventGroup"><arg type="a(isvu)" direction="in"/><arg type="ai" direction="out"/></method>
  <method name="AboutToShow"><arg type="i" direction="in"/><arg type="b" direction="out"/></method>
  <method name="AboutToShowGroup"><arg type="ai" direction="in"/><arg type="ai" direction="out"/><arg type="ai" direction="out"/></method>
  <signal name="LayoutUpdated"><arg type="u"/><arg type="i"/></signal>
  <signal name="ItemsPropertiesUpdated"><arg type="a(ia{sv})"/><arg type="a(ias)"/></signal>
</interface></node>`;
const loop = new GLib.MainLoop(null, false);
const bus = Gio.bus_get_sync(Gio.BusType.SESSION, null);
const exports = [];
const items = [];
const properties = (id, updated = false) =>
  id === 0
    ? { "children-display": new GLib.Variant("s", "submenu") }
    : {
        label: new GLib.Variant(
          "s",
          updated ? "Updated smoke action" : "Smoke menu action",
        ),
        enabled: new GLib.Variant("b", true),
        visible: new GLib.Variant("b", true),
      };

for (const [path, isMenu] of [
  ["/MenuItem", true],
  ["/ActiveItem", false],
]) {
  // Astal's watcher tracks one item per unique bus owner, as most apps do.
  const connection = Gio.DBusConnection.new_for_address_sync(
    GLib.getenv("DBUS_SESSION_BUS_ADDRESS"),
    Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT |
      Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
    null,
    null,
  );
  items.push({ connection, path });
  const item = Gio.DBusExportedObject.wrapJSObject(itemXml, {
    Category: "ApplicationStatus",
    Id: path.slice(1),
    Title: path.slice(1),
    Status: "Active",
    WindowId: 0,
    IconName: "application-x-executable-symbolic",
    IconPixmap: [],
    OverlayIconName: "",
    OverlayIconPixmap: [],
    AttentionIconName: "",
    AttentionIconPixmap: [],
    AttentionMovieName: "",
    ToolTip: ["", [], path.slice(1), "Private smoke fixture"],
    ItemIsMenu: isMenu,
    Menu: `${path}/Menu`,
    Activate() {
      print(`TRAY_ACTIVATE ${path}`);
    },
    SecondaryActivate() {
      print(`TRAY_SECONDARY ${path}`);
    },
    ContextMenu() {
      print(`TRAY_CONTEXT ${path}`);
    },
    Scroll(delta, orientation) {
      print(`TRAY_SCROLL ${path} ${delta} ${orientation}`);
    },
  });
  item.export(connection, path);
  let updated = false;
  let updateScheduled = false;
  const menu = Gio.DBusExportedObject.wrapJSObject(menuXml, {
    Version: 3,
    TextDirection: "ltr",
    Status: "normal",
    IconThemePath: [],
    GetLayout() {
      print(`TRAY_LAYOUT ${path}`);
      return [
        updated ? 2 : 1,
        [
          0,
          properties(0),
          [new GLib.Variant("(ia{sv}av)", [1, properties(1, updated), []])],
        ],
      ];
    },
    GetGroupProperties(ids) {
      return ids.map((id) => [id, properties(id, updated)]);
    },
    GetProperty(id, name) {
      return properties(id, updated)[name] || new GLib.Variant("s", "");
    },
    Event(id, event) {
      print(`TRAY_EVENT ${path} ${id} ${event}`);
    },
    EventGroup(events) {
      for (const [id, event] of events)
        print(`TRAY_EVENT ${path} ${id} ${event}`);
      return [];
    },
    AboutToShow() {
      print(`TRAY_ABOUT_TO_SHOW ${path}`);
      if (!updateScheduled) {
        updateScheduled = true;
        GLib.timeout_add(GLib.PRIORITY_DEFAULT, 80, () => {
          updated = true;
          print(`TRAY_DYNAMIC_UPDATE ${path}`);
          menu.emit_signal("LayoutUpdated", new GLib.Variant("(ui)", [2, 0]));
          return GLib.SOURCE_REMOVE;
        });
      }
      return false;
    },
    AboutToShowGroup() {
      return [[], []];
    },
  });
  menu.export(connection, `${path}/Menu`);
  exports.push(item, menu);
}
const control = Gio.DBusExportedObject.wrapJSObject(
  '<node><interface name="dev.framework.Smoke"><method name="Remove"/></interface></node>',
  {
    Remove() {
      print("TRAY_REMOVE");
      GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
        for (const { connection } of items) connection.close_sync(null);
        loop.quit();
        return GLib.SOURCE_REMOVE;
      });
    },
  },
);
control.export(bus, "/Smoke");
exports.push(control);
Gio.bus_own_name_on_connection(
  bus,
  "dev.framework.SmokeTray",
  Gio.BusNameOwnerFlags.NONE,
  null,
  null,
);
Gio.bus_watch_name_on_connection(
  bus,
  "org.kde.StatusNotifierWatcher",
  Gio.BusNameWatcherFlags.NONE,
  () => {
    for (const { connection, path } of items)
      connection.call(
        "org.kde.StatusNotifierWatcher",
        "/StatusNotifierWatcher",
        "org.kde.StatusNotifierWatcher",
        "RegisterStatusNotifierItem",
        new GLib.Variant("(s)", [path]),
        null,
        Gio.DBusCallFlags.NONE,
        2000,
        null,
        (connection, result) => {
          try {
            connection.call_finish(result);
            print(`TRAY_REGISTERED ${path}`);
          } catch (error) {
            printerr(error);
          }
        },
      );
  },
  null,
);
print("TRAY_FIXTURE_READY");
loop.run();
