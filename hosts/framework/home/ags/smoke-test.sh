#!/usr/bin/env bash
# Smoke-test the AGS UI without connecting to the running desktop or its services.
# Usage: AGS=/nix/store/...-ags LABWC=/nix/store/...-labwc \
#   SASS=/nix/store/...-dart-sass THEME_SCSS=/nix/store/...-themegen-cache-framework/.config/ags/theme-dark.scss \
#   bash hosts/framework/home/ags/smoke-test.sh
set -euo pipefail
: "${AGS:?provide the built AGS package path}"
: "${LABWC:?provide the built labwc package path}"
: "${SASS:?provide the built dart-sass package path}"
: "${THEME_SCSS:?provide a rendered theme-light.scss or theme-dark.scss path}"
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
umask 077
work=$(mktemp -d /tmp/framework-ags-smoke.XXXXXXXX)
cleanup() {
  if [[ -n "${labwc_pid:-}" ]]; then
    kill "$labwc_pid" 2>/dev/null || :
    wait "$labwc_pid" 2>/dev/null || :
  fi
  if [[ "${KEEP_SMOKE_LOGS:-0}" = 1 ]]; then
    printf 'Smoke logs: %s\n' "$work"
  else
    rm -rf -- "$work"
  fi
}
trap cleanup EXIT
export HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" XDG_RUNTIME_DIR="$work/runtime"
mkdir -p "$HOME" "$XDG_CONFIG_HOME/ags" "$XDG_RUNTIME_DIR" "$work/labwc"
cp "$source_dir/app.tsx" "$source_dir/style.scss" "$XDG_CONFIG_HOME/ags/"
cp "$THEME_SCSS" "$XDG_CONFIG_HOME/ags/theme.scss"
"$SASS/bin/sass" --no-source-map "$XDG_CONFIG_HOME/ags/style.scss" "$XDG_CONFIG_HOME/ags/style.css" > "$work/sass.log" 2>&1

# Inject test-only interactions into the private copy. Production app.tsx is unchanged.
python3 - "$XDG_CONFIG_HOME/ags/app.tsx" <<'PY'
import sys
path = sys.argv[1]
with open(path) as fh:
    source = fh.read()
marker = '    const daemon = subprocess('
assert source.count(marker) == 1, 'expected exactly one daemon startup in App.start'
probe = '''    print(`SMOKE_MONITORS count=${App.get_monitors().length}`)
    const first = App.get_monitors()[0]
    if (first) {
      const children = (widget) => widget.get_children?.() || (widget.get_child?.() ? [widget.get_child()] : [])
      const find = (widget, className) => {
        if (widget.get_style_context().has_class(className)) return widget
        for (const child of children(widget)) {
          const match = find(child, className)
          if (match) return match
        }
        return null
      }
      const assert = (condition, message) => { if (!condition) throw Error(`SMOKE_WIDGET ${message}`) }
      GLib.timeout_add(GLib.PRIORITY_DEFAULT, 500, () => {
        const bars = App.get_windows().filter((window) => window.name.startsWith("bar-"))
        assert(bars.length === 2, `expected two bars, got ${bars.length}`)
        const widgets = bars.map((bar) => {
          const battery = find(bar, "battery")
          const tray = find(bar, "tray")
          const ring = find(bar, "battery-ring")
          const ringSlot = find(bar, "ring-slot")
          const traySlot = find(bar, "tray-slot")
          const peers = [find(bar, "perf"), find(bar, "datetime"), find(bar, "control-button")]
          const batteryReveal = find(bar, "battery-device-revealer")
          const trayReveal = find(bar, "tray-revealer")
          assert([battery, tray, ring, ringSlot, traySlot, batteryReveal, trayReveal].every(Boolean), "missing battery/tray widget")
          assert(peers.every(Boolean), "missing peer widgets for height comparison")
          const height = peers[0].get_allocated_height()
          assert([battery, tray, ...peers].every((widget) => widget.get_allocated_height() === height),
            `outer widget heights differ: ${[battery, tray, ...peers].map((widget) => widget.get_allocated_height()).join(", ")}`)
          assert(Math.abs(ring.startAt - 0.75) < 0.001 && Math.abs(ring.endAt - 0.75) < 0.001, "ring endpoints")
          assert(ring.get_allocated_width() === 32 && ring.get_allocated_height() === 32, "ring must be 32x32")
          assert(ringSlot.get_allocated_width() === 40 && ringSlot.get_allocated_height() === 32, "ring slot must be 40x32")
          assert(traySlot.get_allocated_width() === 40 && traySlot.get_allocated_height() === 32, "tray slot must be 40x32")
          assert(ring.get_style_context().get_property("font-size", Gtk.StateFlags.NORMAL) === 3, "ring stroke font-size must be 3px")
          return { battery, tray, batteryReveal, trayReveal }
        })
        for (const type of ["battery", "tray"]) {
          const reveal = `${type}Reveal`
          assert(widgets.every((widget) => !widget[reveal].revealChild), `${type} initially revealed`)
          widgets[0][type].emit("hover", null)
          GLib.timeout_add(GLib.PRIORITY_DEFAULT, 100, () => {
            assert(widgets[0][reveal].revealChild && !widgets[1][reveal].revealChild, `${type} hover leaked between monitors (${widgets[0][reveal].revealChild}, ${widgets[1][reveal].revealChild})`)
            widgets[0][type].emit("hover-lost", null)
            GLib.timeout_add(GLib.PRIORITY_DEFAULT, 100, () => {
              assert(!widgets[0][reveal].revealChild && !widgets[1][reveal].revealChild, `${type} stayed revealed after leave`)
              print(`SMOKE_WIDGET_${type.toUpperCase()}_PASS`)
              return GLib.SOURCE_REMOVE
            })
            return GLib.SOURCE_REMOVE
          })
        }
        const panel = overlays.get(first).control
        const rows = []
        const collectRows = (widget) => {
          if (widget.get_style_context().has_class("cc-slider-row")) rows.push(widget)
          children(widget).forEach(collectRows)
        }
        collectRows(panel)
        assert(rows.length === 2, `expected volume/brightness rows, got ${rows.length}`)
        const positions = rows.map((row) => {
          const slot = find(row, "slider-icon")
          const image = slot.get_child?.() || slot.get_children()[0]
          const scale = find(row, "cc-scale")
          assert(slot.get_allocated_width() === 34 && slot.get_allocated_height() === 34,
            `slider icon slot must be 34x34, got ${slot.get_allocated_width()}x${slot.get_allocated_height()}`)
          assert(image.get_style_context().get_property("font-size", Gtk.StateFlags.NORMAL) === 22, "slider icons must both be 22px")
          const [valid, x, y] = image.translate_coordinates(panel, 0, 0)
          const [rowValid, , rowY] = row.translate_coordinates(panel, 0, 0)
          const [scaleValid, scaleX] = scale.translate_coordinates(panel, 0, 0)
          assert(valid && rowValid && scaleValid, "unable to locate slider icon")
          const centerX = x + image.get_allocated_width() / 2
          const centerY = y + image.get_allocated_height() / 2
          assert(Math.abs(centerY - rowY - row.get_allocated_height() / 2) <= 1, "slider icon is not vertically centered")
          return { centerX, scaleX }
        })
        assert(positions[0].centerX === positions[1].centerX, "volume and brightness icon centers differ")
        assert(positions[0].scaleX === positions[1].scaleX, "volume and brightness slider starts differ")
        print("SMOKE_SLIDER_ALIGNMENT_PASS")
        print("SMOKE_WIDGET_PASS")
        return GLib.SOURCE_REMOVE
      })
      let step = 0
      GLib.timeout_add(GLib.PRIORITY_DEFAULT, 300, () => {
        print(`SMOKE_VIEW step=${step}`)
        switch (step++) {
          case 0: toggle(first, "control"); break
          case 1: openView("wifi"); break
          case 2: openView("sound"); break
          case 3: openView("notifications"); break
          case 4: openView("session"); break
          case 5: close(first); toggle(first, "calendar"); break
          case 6: close(first); print("SMOKE_PASS"); break
          default: return GLib.SOURCE_REMOVE
        }
        return GLib.SOURCE_CONTINUE
      })
    }
'''
with open(path, 'w') as fh:
    fh.write(source.replace(marker, probe + marker))
PY

# Use safe local fixtures; no Niri, audio, Wi-Fi, notifications or real tray access.
python3 - "$work/patch.json" "$XDG_CONFIG_HOME/ags/config.json" "$work" <<'PY'
import json,sys
patch,config,work=sys.argv[1:]
with open(patch,'w') as fh:
    json.dump({'datetime_time':'12:00','datetime_date':'2026-09-26','battery_value':'50',
      'battery_tooltip':'Battery 50 percent','network_label':'Network test','audio_speaker_value':'45',
      'notifications_count':'1',
      'notifications_history':json.dumps([{'key':'synthetic:1','class':'normal','app':'Mock',
        'summary':'Test notification','preview':'Test notification preview','body':'Test body',
        'source':'history','unread':True}]),
      'niri_groups':json.dumps([{'monitor':f'HEADLESS-{i}','workspaces':[{'label':str(i),
        'windows':[{'id':i,'title':'Synthetic Window','focused':i==1,
        'icon_path':work+'/mock-symbolic.svg'}]}]} for i in (1,2)])},fh)
keys='appPlaceholder batteryAc batteryBat batteryUnknown brightness controlCenter media micActive micMuted network notification speakerHigh speakerLow speakerMuted tray bluetooth clear darkMode lock logout reboot shutdown suspend lidSleep'.split()
with open(config,'w') as fh:
    json.dump({'stateBinary':work+'/fake-state','stateConfig':work+'/fake-config',
      'ccCtl':work+'/fake-ctl','ccCmd':work+'/fake-ctl','ccWifi':work+'/fake-ctl',
      'icons':{key:work+'/mock-symbolic.svg' for key in keys}},fh)
PY
printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><rect width="24" height="24" fill="black"/></svg>' > "$work/mock-symbolic.svg"
# shellcheck disable=SC2016 # These are literal shell expressions in generated fixtures.
printf '%s\n' '#!/usr/bin/env bash' 'if [[ "${*: -1}" == daemon ]]; then cat "$(dirname "$0")/patch.json"; echo; sleep 15; else exit 0; fi' > "$work/fake-state"
# shellcheck disable=SC2016 # Literal expressions are evaluated by the generated script.
printf '%s\n' '#!/usr/bin/env bash' 'case "${1:-}" in state) echo off ;; scan|rescan|connect|disconnect) echo '\''[{"ssid":"Known","signal":80,"security":"WPA2","known":true,"active":true},{"ssid":"Open","signal":60,"security":"","known":false,"active":false},{"ssid":"Locked","signal":40,"security":"WPA2","known":false,"active":false}]'\'' ;; esac' > "$work/fake-ctl"
chmod +x "$work/fake-state" "$work/fake-ctl"
printf '{}\n' > "$work/fake-config"
printf '%s\n' '<?xml version="1.0"?><labwc_config><core><xwayland>no</xwayland></core></labwc_config>' > "$work/labwc/rc.xml"

# labwc's wlroots headless backend implements the layer-shell protocol.
unset WAYLAND_DISPLAY DISPLAY DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID NIRI_SOCKET SWAYSOCK
export GDK_BACKEND=wayland WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=2
export WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman
"$LABWC/bin/labwc" -C "$work/labwc" > "$work/labwc.log" 2>&1 &
labwc_pid=$!
for ((i=0; i<80; i++)); do
  if [[ -S "$XDG_RUNTIME_DIR/wayland-0" ]]; then break; fi
  if ! kill -0 "$labwc_pid" 2>/dev/null; then
    printf 'Isolated compositor exited unexpectedly:\n' >&2
    tail -40 "$work/labwc.log" >&2
    exit 1
  fi
  sleep 0.1
done
if [[ ! -S "$XDG_RUNTIME_DIR/wayland-0" ]]; then
  printf 'Isolated compositor socket did not appear\n' >&2
  tail -40 "$work/labwc.log" >&2
  exit 1
fi
export WAYLAND_DISPLAY=wayland-0

# dbus-run-session owns and reaps its bus. timeout bounds the UI and descendants;
# the private compositor is explicitly reaped by the EXIT trap.
set +e
timeout --signal=TERM --kill-after=3 6s dbus-run-session -- "$AGS/bin/ags" run "$XDG_CONFIG_HOME/ags/app.tsx" > "$work/ags.log" 2>&1
status=$?
set -e
if [[ "$status" != 124 ]]; then
  printf 'AGS quit unexpectedly (%s):\n' "$status" >&2
  tail -80 "$work/ags.log" >&2
  exit 1
fi
if ! grep -q 'SMOKE_MONITORS count=2' "$work/ags.log" || ! grep -q 'SMOKE_WIDGET_PASS' "$work/ags.log" || ! grep -q 'SMOKE_WIDGET_BATTERY_PASS' "$work/ags.log" || ! grep -q 'SMOKE_WIDGET_TRAY_PASS' "$work/ags.log" || ! grep -q 'SMOKE_SLIDER_ALIGNMENT_PASS' "$work/ags.log" || ! grep -q 'SMOKE_PASS' "$work/ags.log"; then
  printf 'Did not exercise both monitors and all control views:\n' >&2
  tail -80 "$work/ags.log" >&2
  exit 1
fi
# timeout can cause shutdown-only bus and process warnings; check every message
# until the successful view marker, without hiding any startup/UI error.
if awk '/SMOKE_PASS/{exit} /CRITICAL|JS ERROR|TypeError|ReferenceError/{print}' "$work/ags.log" | grep .; then
  printf 'AGS emitted a critical error before completing the UI smoke\n' >&2
  exit 1
fi
printf 'AGS headless smoke passed (2 monitors; control, Wi-Fi, sound, notifications, session, calendar).\n'
