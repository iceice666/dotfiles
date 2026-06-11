// Sunrise/sunset appearance switcher for macOS.
// Defaults to Taipei coordinates (UTC+8); override with --lat, --lon, --tz-offset-hours.
// Reads dark-mode state via `defaults read -g AppleInterfaceStyle` and switches
// via `osascript`. Designed to run once per launchd interval (e.g. every 600 s).

use std::f64::consts::PI;
use std::process::{exit, Command};
use std::time::{SystemTime, UNIX_EPOCH};

const DEFAULT_LAT: f64 = 25.0330;
const DEFAULT_LON: f64 = 121.5654;
const DEFAULT_TZ_OFFSET_HOURS: f64 = 8.0; // Asia/Taipei

const ZENITH: f64 = 90.833;
const SUNRISE_OFFSET_SECS: i64 = 30 * 60; // light mode starts 30 min after sunrise
const SUNSET_OFFSET_SECS: i64 = -30 * 60; // dark mode starts 30 min before sunset

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let lat = parse_f64(&args, "--lat").unwrap_or(DEFAULT_LAT);
    let lon = parse_f64(&args, "--lon").unwrap_or(DEFAULT_LON);
    let tz_offset_hours = parse_f64(&args, "--tz-offset-hours").unwrap_or(DEFAULT_TZ_OFFSET_HOURS);
    let tz_secs = (tz_offset_hours * 3600.0) as i64;

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system time before UNIX epoch")
        .as_secs() as i64;

    let (doy, day_start) = day_info(now, tz_secs);

    let Some(sr) = solar_event(doy, lat, lon, tz_secs, true, day_start) else {
        log("Could not calculate sunrise.");
        exit(1);
    };
    let Some(ss) = solar_event(doy, lat, lon, tz_secs, false, day_start) else {
        log("Could not calculate sunset.");
        exit(1);
    };

    let light_start = sr + SUNRISE_OFFSET_SECS;
    let dark_start = ss + SUNSET_OFFSET_SECS;
    let want_dark = now < light_start || now >= dark_start;

    log(&format!("Sunrise+30m: {}", fmt_hhmm(light_start, tz_secs)));
    log(&format!("Sunset-30m:  {}", fmt_hhmm(dark_start, tz_secs)));

    if current_dark_mode() == want_dark {
        log("Appearance already matches target mode.");
        return;
    }

    set_dark_mode(want_dark);
}

// ── arg parsing ────────────────────────────────────────────────────────────────

fn parse_f64(args: &[String], flag: &str) -> Option<f64> {
    let i = args.iter().position(|a| a == flag)?;
    args.get(i + 1)?.parse().ok()
}

// ── calendar helpers ───────────────────────────────────────────────────────────

/// Returns (day_of_year [1-indexed], unix timestamp of local midnight).
fn day_info(unix_secs: i64, tz_secs: i64) -> (u32, i64) {
    let local = unix_secs + tz_secs;
    let days = local.div_euclid(86400);

    let mut rem = days as i32;
    let mut year = 1970i32;
    while rem >= days_in_year(year) {
        rem -= days_in_year(year);
        year += 1;
    }

    let doy = rem as u32 + 1;
    let day_start_unix = days * 86400 - tz_secs;
    (doy, day_start_unix)
}

fn days_in_year(y: i32) -> i32 {
    if is_leap(y) { 366 } else { 365 }
}

fn is_leap(y: i32) -> bool {
    (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0)
}

// ── solar algorithm ────────────────────────────────────────────────────────────
// Translated directly from the Swift implementation (USNO algorithm).

fn solar_event(
    doy: u32,
    lat: f64,
    lon: f64,
    tz_secs: i64,
    is_sunrise: bool,
    day_start: i64,
) -> Option<i64> {
    let lng_hour = lon / 15.0;
    let base = if is_sunrise { 6.0 } else { 18.0 };
    let t = doy as f64 + ((base - lng_hour) / 24.0);
    let mean_anomaly = 0.9856 * t - 3.289;

    let mut true_lon =
        mean_anomaly + 1.916 * sin_d(mean_anomaly) + 0.020 * sin_d(2.0 * mean_anomaly) + 282.634;
    true_lon = norm_deg(true_lon);

    let mut ra = norm_deg(atan_d(0.91764 * tan_d(true_lon)));
    ra += (true_lon / 90.0).floor() * 90.0 - (ra / 90.0).floor() * 90.0;
    ra /= 15.0;

    let sin_decl = 0.39782 * sin_d(true_lon);
    let cos_decl = sin_decl.asin().cos();
    let cos_lh = (cos_d(ZENITH) - sin_decl * sin_d(lat)) / (cos_decl * cos_d(lat));

    if !(-1.0..=1.0).contains(&cos_lh) {
        return None; // sun never rises/sets (polar day/night)
    }

    let mut lh = acos_d(cos_lh);
    if is_sunrise {
        lh = 360.0 - lh;
    }
    lh /= 15.0;

    let lmt = lh + ra - 0.06571 * t - 6.622;
    let ut = norm_hours(lmt - lng_hour);
    let local_time = norm_hours(ut + tz_secs as f64 / 3600.0);

    Some(day_start + (local_time * 3600.0).round() as i64)
}

// ── macOS appearance ───────────────────────────────────────────────────────────

fn current_dark_mode() -> bool {
    Command::new("/usr/bin/defaults")
        .args(["read", "-g", "AppleInterfaceStyle"])
        .output()
        .map(|o| {
            o.status.success()
                && String::from_utf8_lossy(&o.stdout)
                    .trim()
                    .eq_ignore_ascii_case("dark")
        })
        .unwrap_or(false)
}

fn set_dark_mode(dark: bool) {
    let script = format!(
        "tell application \"System Events\" to tell appearance preferences to set dark mode to {}",
        dark
    );
    match Command::new("/usr/bin/osascript").args(["-e", &script]).status() {
        Ok(s) if s.success() => {
            log(&format!("Switched to {} mode.", if dark { "dark" } else { "light" }));
        }
        _ => {
            log("Failed to switch appearance.");
            exit(1);
        }
    }
}

// ── utilities ─────────────────────────────────────────────────────────────────

fn fmt_hhmm(unix_secs: i64, tz_secs: i64) -> String {
    let s = (unix_secs + tz_secs).rem_euclid(86400);
    format!("{:02}:{:02}", s / 3600, (s % 3600) / 60)
}

fn log(msg: &str) {
    println!("[appearance-scheduler] {msg}");
}

// ── trig in degrees ───────────────────────────────────────────────────────────

fn sin_d(d: f64) -> f64 { (d * PI / 180.0).sin() }
fn cos_d(d: f64) -> f64 { (d * PI / 180.0).cos() }
fn tan_d(d: f64) -> f64 { (d * PI / 180.0).tan() }
fn atan_d(x: f64) -> f64 { x.atan() * 180.0 / PI }
fn acos_d(x: f64) -> f64 { x.acos() * 180.0 / PI }

fn norm_deg(v: f64) -> f64 { v.rem_euclid(360.0) }
fn norm_hours(v: f64) -> f64 { v.rem_euclid(24.0) }
