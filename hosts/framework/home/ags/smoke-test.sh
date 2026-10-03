#!/usr/bin/env bash
# Smoke-test the AGS UI without connecting to the running desktop or its services.
# Usage: AGS=/nix/store/...-ags LABWC=/nix/store/...-labwc \
#   SASS=/nix/store/...-dart-sass THEME_SCSS=/nix/store/...-themegen-cache-framework/.config/ags/theme-dark.scss \
#   bash hosts/framework/home/ags/smoke-test.sh
# Optional: KEEP_SMOKE_LOGS=1 SMOKE_GRIM=/absolute/path/to/grim retains a screenshot.
set -euo pipefail
: "${AGS:?provide the built AGS package path}"
: "${AGS_LAUNCHER:?provide the built framework-ags runtime wrapper path}"
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
export XDG_CACHE_HOME="$work/cache" XDG_DATA_HOME="$work/data" XDG_STATE_HOME="$work/state"
export GSETTINGS_BACKEND=memory GIO_USE_VFS=local GTK_A11Y=none FRAMEWORK_AGS_SMOKE=1
# A private bus is insufficient for tools that fall back to the system bus.
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=$work/no-system-bus"
mkdir -p "$HOME" "$XDG_CONFIG_HOME/ags" "$XDG_RUNTIME_DIR" "$work/labwc"
cp "$source_dir/app.tsx" "$source_dir/style.scss" "$XDG_CONFIG_HOME/ags/"
cp "$THEME_SCSS" "$XDG_CONFIG_HOME/ags/theme.scss"
"$SASS/bin/sass" --no-source-map "$XDG_CONFIG_HOME/ags/style.scss" "$XDG_CONFIG_HOME/ags/style.css" > "$work/sass.log" 2>&1

# Copy the shared modules, then inject a probe into the private entrypoint only.
cp "$source_dir/state.ts" "$source_dir/control-center.tsx" "$source_dir/notifications.tsx" "$source_dir/smoke-probe.ts" "$XDG_CONFIG_HOME/ags/"
cp "$source_dir/smoke-tray.js" "$work/"
python3 - "$XDG_CONFIG_HOME/ags/app.tsx" <<'PYPROBE'
import sys
path = sys.argv[1]
with open(path) as fh:
    source = fh.read()
marker = '    const daemon = subprocess('
assert source.count(marker) == 1, 'expected exactly one daemon startup in app.start'
probe = '    void runSmoke({ app, Gtk, Gdk, GLib, Gio, overlays, toggle, close, openView, mount });\n'
with open(path, 'w') as fh:
    fh.write('import { runSmoke } from "./smoke-probe";\n' + source.replace(marker, probe + marker))
PYPROBE

# Use safe local fixtures; no Niri, audio, Wi-Fi or real tray access. Notifications
# go through AstalNotifd on the private bus with in-memory GSettings.
python3 - "$work/patch.json" "$XDG_CONFIG_HOME/ags/config.json" "$work" <<'PY'
import json,sys
patch,config,work=sys.argv[1:]
with open(patch,'w') as fh:
    json.dump({'datetime_time':'12:00','datetime_date':'2026-09-26','battery_value':'50',
      'battery_tooltip':'Battery 50 percent','network_label':'Network test','audio_speaker_value':'55',
      'audio_speaker_percent':'55%','brightness_value':'65','brightness_text':'65%',
      'perf_cpu':'12%','perf_ram':'4.2G','perf_gpu':'45°','perf_up':'2K','perf_down':'84K',
      'media_text':'Synthetic Artist — Synthetic Song',
      'niri_groups':json.dumps([{'monitor':f'HEADLESS-{i}','workspaces':[{'label':str(i),
        'windows':[{'id':i,'title':'Synthetic Window','focused':i==1,
        'icon_path':work+'/mock-symbolic.svg'}]}]} for i in (1,2)])},fh)
keys='appPlaceholder batteryAc batteryBat batteryUnknown brightness controlCenter media micActive micMuted network notification speakerHigh speakerLow speakerMuted tray bluetooth clear darkMode lock logout reboot shutdown hibernate lidSleep'.split()
with open(config,'w') as fh:
    json.dump({'stateBinary':work+'/fake-state','stateConfig':work+'/fake-config',
      'ccCtl':work+'/fake-ctl','ccCmd':work+'/fake-ctl','ccWifi':work+'/fake-ctl',
      'icons':{key:work+'/mock-symbolic.svg' for key in keys}},fh)
PY
printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8" fill="none" stroke="#808080" stroke-width="2"/><path d="M8 12h8m-4-4v8" stroke="#808080" stroke-width="2"/></svg>' > "$work/mock-symbolic.svg"
# shellcheck disable=SC2016 # These are literal shell expressions in generated fixtures.
printf '%s\n' '#!/usr/bin/env bash' 'if [[ "${*: -1}" == daemon ]]; then cat "$(dirname "$0")/patch.json"; echo; exec sleep 20; else printf "%s\n" "$*" >> "$(dirname "$0")/actions.log"; fi' > "$work/fake-state"
# shellcheck disable=SC2016 # Literal expressions are evaluated by the generated script.
printf '%s\n' '#!/usr/bin/env bash' 'if [[ "${1:-}" == connect && "${2:-}" == Locked ]]; then exit 1; fi' 'case "${1:-}" in state) echo off ;; scan|rescan|connect|disconnect) echo '\''[{"ssid":"Known","signal":80,"security":"WPA2","known":true,"active":true},{"ssid":"Open","signal":60,"security":"","known":false,"active":false},{"ssid":"Locked","signal":40,"security":"WPA2","known":false,"active":false}]'\'' ;; esac' > "$work/fake-ctl"
chmod +x "$work/fake-state" "$work/fake-ctl"
printf '{}\n' > "$work/fake-config"
printf '%s\n' '<?xml version="1.0"?><labwc_config><core><xwayland>no</xwayland></core></labwc_config>' > "$work/labwc/rc.xml"

# labwc's wlroots headless backend implements the layer-shell protocol.
unset WAYLAND_DISPLAY DISPLAY DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID NIRI_SOCKET SWAYSOCK
export GDK_BACKEND=wayland GSK_RENDERER=cairo WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=2
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

# AGS 3 emits an executable launcher: exercise it directly as systemd does.
"$AGS/bin/ags" bundle "$XDG_CONFIG_HOME/ags/app.tsx" "$XDG_CONFIG_HOME/ags/app.js" > "$work/bundle.log" 2>&1

# Both GJS processes share only this private bus. AGS uses a fixed intermediate
# filename under XDG_RUNTIME_DIR, so give the fixture its own runtime directory.
mkdir -p "$work/tray-runtime"
export AGS AGS_LAUNCHER work
set +e
# Disable service activation as well: inherited system data dirs otherwise let
# GTK start portal daemons in the private bus unnecessarily.
printf '%s\n' '<busconfig><type>session</type><listen>unix:tmpdir=/tmp</listen><auth>EXTERNAL</auth><policy context="default"><allow send_destination="*"/><allow receive_sender="*"/><allow own="*"/></policy></busconfig>' > "$work/dbus.conf"
timeout --signal=TERM --kill-after=3 20s dbus-run-session --config-file="$work/dbus.conf" -- bash -c '
  set -euo pipefail
  XDG_RUNTIME_DIR="$work/tray-runtime" "$AGS/bin/ags" run --gtk 4 "$work/smoke-tray.js" > "$work/tray.log" 2>&1 &
  fixture=$!
  cleanup_fixture() { kill "$fixture" 2>/dev/null || :; wait "$fixture" 2>/dev/null || :; }
  trap cleanup_fixture EXIT
  "$AGS_LAUNCHER" "$XDG_CONFIG_HOME/ags/app.js"
' > "$work/ags.log" 2>&1
status=$?
set -e
if [[ "$status" != 0 ]]; then
  printf 'AGS smoke exited unexpectedly (%s):\n' "$status" >&2
  tail -n 80 "$work/ags.log" "$work/tray.log" >&2
  exit 1
fi
for marker in 'SMOKE_MONITORS count=2' SMOKE_WIDGET_PASS SMOKE_WIDGET_BATTERY_PASS SMOKE_WIDGET_TRAY_PASS SMOKE_SLIDER_ALIGNMENT_PASS SMOKE_SLIDER_ACTIONS_PASS SMOKE_TRAY_PASS SMOKE_TRAY_DYNAMIC_PASS SMOKE_LIFECYCLE_PASS SMOKE_WIFI_PASS SMOKE_NOTIFICATIONS_PASS SMOKE_PASS; do
  if ! grep -q "$marker" "$work/ags.log"; then
    printf 'Missing UI assertion: %s\n' "$marker" >&2
    tail -n 80 "$work/ags.log" "$work/tray.log" >&2
    exit 1
  fi
done
for marker in 'TRAY_ACTIVATE /ActiveItem' 'TRAY_SECONDARY /ActiveItem' 'TRAY_SCROLL /ActiveItem 1 vertical' 'TRAY_SCROLL /ActiveItem -1 horizontal' 'TRAY_EVENT /MenuItem 1 clicked' 'TRAY_DYNAMIC_UPDATE /MenuItem' TRAY_REMOVE; do
  if ! grep -q "$marker" "$work/tray.log"; then
    printf 'Missing real D-Bus fixture event: %s\n' "$marker" >&2
    tail -n 80 "$work/ags.log" "$work/tray.log" >&2
    exit 1
  fi
done
if grep -E 'CRITICAL|JS ERROR|TypeError|ReferenceError|SMOKE_FAIL|smoke-private-password|Gtk-WARNING|Theme parser error' "$work/ags.log" "$work/tray.log" "$work/actions.log"; then
  printf 'AGS or tray fixture emitted an error\n' >&2
  exit 1
fi
printf 'AGS GTK4 smoke passed (2 monitors; all control views; isolated hover; slider alignment; notifications/DND; DBusMenu and tray actions/removal).\n'
