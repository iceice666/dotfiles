use std::path::PathBuf;

use iced::Color;
use serde::{Deserialize, Serialize};

use crate::{Config, NiriGroup, NotificationRow, Vars, theme_color};

#[derive(Debug, Clone)]
pub struct DeviceAudio {
    pub value: u8,
    pub percent: String,
    pub icon: PathBuf,
    pub text: String,
    pub color: Color,
    pub class: String,
    pub device: String,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct WifiNetwork {
    pub active: bool,
    pub signal: i64,
    pub security: String,
    pub ssid: String,
    pub known: bool,
}

#[derive(Debug, Clone)]
pub struct BarData {
    pub niri_groups: Vec<NiriGroup>,
    pub media_text: String,
    pub perf_cpu: String,
    pub perf_ram: String,
    pub perf_gpu: String,
    pub perf_up: String,
    pub perf_down: String,
    pub battery_value: f32,
    pub battery_tooltip: String,
    pub battery_icon: PathBuf,
    pub battery_color: Color,
    pub battery_class: String,
    pub audio_speaker: DeviceAudio,
    pub audio_mic: DeviceAudio,
    pub brightness_value: f32,
    pub brightness_text: String,
    pub network_label: String,
    pub network_detail: String,
    pub network_class: String,
    pub datetime_date: String,
    pub datetime_time: String,
    pub notifications_count: u32,
    pub notifications_label: String,
    pub notifications_color: Color,
    pub notifications_class: String,
    pub notifications_history_count: u32,
    pub notifications_history: Vec<NotificationRow>,
    pub cc_icon: Color,
    pub cc_accent: Color,
    pub cc_on_accent: Color,
    pub cc_wifi: bool,
    pub cc_bt: bool,
    pub cc_dnd: bool,
    pub cc_dark: bool,
    pub wifi_networks: Vec<WifiNetwork>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CcView {
    Home,
    Wifi,
    Sound,
    Notifications,
    Session,
}

#[derive(Debug, Clone)]
pub struct UiState {
    pub battery_revealed: bool,
    pub systray_revealed: bool,
    pub audio_speaker_revealed: bool,
    pub audio_mic_revealed: bool,
    pub notification_expanded_id: String,
    pub cc_view: CcView,
    pub wifi_password: String,
    pub wifi_pw_target: String,
}

#[derive(Debug, Clone, Copy)]
pub struct Palette {
    pub background: Color,
    pub critical: Color,
    pub foreground: Color,
    pub foreground_dim: Color,
    pub on_critical: Color,
    pub on_primary: Color,
    pub outline: Color,
    pub primary: Color,
    pub success: Color,
    pub surface: Color,
    pub surface_active: Color,
    pub surface_container: Color,
    pub surface_hover: Color,
    pub warning: Color,
}

impl Default for DeviceAudio {
    fn default() -> Self {
        Self {
            value: 0,
            percent: "0%".to_string(),
            icon: PathBuf::new(),
            text: "--".to_string(),
            color: color_hex("#e5e5e5"),
            class: String::new(),
            device: String::new(),
        }
    }
}

impl Default for BarData {
    fn default() -> Self {
        Self {
            niri_groups: Vec::new(),
            media_text: String::new(),
            perf_cpu: "--".to_string(),
            perf_ram: "--".to_string(),
            perf_gpu: "--".to_string(),
            perf_up: "--".to_string(),
            perf_down: "--".to_string(),
            battery_value: 0.0,
            battery_tooltip: "Battery --".to_string(),
            battery_icon: PathBuf::new(),
            battery_color: color_hex("#e5e5e5"),
            battery_class: "island battery".to_string(),
            audio_speaker: DeviceAudio {
                text: "Output --".to_string(),
                device: "Output".to_string(),
                class: "audio-control speaker".to_string(),
                ..DeviceAudio::default()
            },
            audio_mic: DeviceAudio {
                text: "Input --".to_string(),
                device: "Input".to_string(),
                class: "audio-control mic".to_string(),
                ..DeviceAudio::default()
            },
            brightness_value: 0.0,
            brightness_text: "0%".to_string(),
            network_label: "Network".to_string(),
            network_detail: "Offline".to_string(),
            network_class: "cc-tile network disconnected".to_string(),
            datetime_date: "--/-- --".to_string(),
            datetime_time: "--:--".to_string(),
            notifications_count: 0,
            notifications_label: "0".to_string(),
            notifications_color: color_hex("#e5e5e5"),
            notifications_class: "island notifications".to_string(),
            notifications_history_count: 0,
            notifications_history: Vec::new(),
            cc_icon: color_hex("#e5e5e5"),
            cc_accent: color_hex("#60a5fa"),
            cc_on_accent: color_hex("#0b0f17"),
            cc_wifi: false,
            cc_bt: false,
            cc_dnd: false,
            cc_dark: false,
            wifi_networks: Vec::new(),
        }
    }
}

impl Default for UiState {
    fn default() -> Self {
        Self {
            battery_revealed: false,
            systray_revealed: false,
            audio_speaker_revealed: false,
            audio_mic_revealed: false,
            notification_expanded_id: "__none".to_string(),
            cc_view: CcView::Home,
            wifi_password: String::new(),
            wifi_pw_target: String::new(),
        }
    }
}

impl Default for Palette {
    fn default() -> Self {
        Self {
            background: color_hex("#0b0f17"),
            critical: color_hex("#ef4444"),
            foreground: color_hex("#e5e5e5"),
            foreground_dim: color_hex("#a3a3a3"),
            on_critical: color_hex("#ffffff"),
            on_primary: color_hex("#0b0f17"),
            outline: color_hex("#334155"),
            primary: color_hex("#60a5fa"),
            success: color_hex("#22c55e"),
            surface: color_hex("#111827"),
            surface_active: color_hex("#1f2937"),
            surface_container: color_hex("#172033"),
            surface_hover: color_hex("#243044"),
            warning: color_hex("#f97316"),
        }
    }
}

impl BarData {
    pub fn apply_vars(&mut self, vars: &Vars) {
        if let Some(value) = vars.get("niri_groups") {
            self.niri_groups = serde_json::from_str(value).unwrap_or_default();
        }
        update_string(vars, "media_text", &mut self.media_text);
        update_string(vars, "perf_cpu", &mut self.perf_cpu);
        update_string(vars, "perf_ram", &mut self.perf_ram);
        update_string(vars, "perf_gpu", &mut self.perf_gpu);
        update_string(vars, "perf_up", &mut self.perf_up);
        update_string(vars, "perf_down", &mut self.perf_down);
        update_f32(vars, "battery_value", &mut self.battery_value);
        update_string(vars, "battery_tooltip", &mut self.battery_tooltip);
        update_path(vars, "battery_icon", &mut self.battery_icon);
        update_color(vars, "battery_color", &mut self.battery_color);
        update_string(vars, "battery_class", &mut self.battery_class);
        update_device(vars, "audio_speaker", &mut self.audio_speaker);
        update_device(vars, "audio_mic", &mut self.audio_mic);
        update_f32(vars, "brightness_value", &mut self.brightness_value);
        update_string(vars, "brightness_text", &mut self.brightness_text);
        update_string(vars, "network_label", &mut self.network_label);
        update_string(vars, "network_detail", &mut self.network_detail);
        update_string(vars, "network_class", &mut self.network_class);
        update_string(vars, "datetime_date", &mut self.datetime_date);
        update_string(vars, "datetime_time", &mut self.datetime_time);
        update_u32(vars, "notifications_count", &mut self.notifications_count);
        update_string(vars, "notifications_label", &mut self.notifications_label);
        update_color(vars, "notifications_color", &mut self.notifications_color);
        update_string(vars, "notifications_class", &mut self.notifications_class);
        update_u32(
            vars,
            "notifications_history_count",
            &mut self.notifications_history_count,
        );
        if let Some(value) = vars.get("notifications_history") {
            self.notifications_history = serde_json::from_str(value).unwrap_or_default();
        }
        update_color(vars, "cc_icon", &mut self.cc_icon);
        update_color(vars, "cc_accent", &mut self.cc_accent);
        update_color(vars, "cc_on_accent", &mut self.cc_on_accent);
        update_bool(vars, "cc_wifi", &mut self.cc_wifi);
        update_bool(vars, "cc_bt", &mut self.cc_bt);
        update_bool(vars, "cc_dnd", &mut self.cc_dnd);
        update_bool(vars, "cc_dark", &mut self.cc_dark);
        if let Some(value) = vars.get("wifi_networks") {
            self.wifi_networks = serde_json::from_str(value).unwrap_or_default();
        }
    }
}

impl Palette {
    pub fn from_config(cfg: &Config) -> Self {
        Self {
            background: parse_scss_color(&theme_color(cfg, "background", "#0b0f17")),
            critical: parse_scss_color(&theme_color(cfg, "critical", "#ef4444")),
            foreground: parse_scss_color(&theme_color(cfg, "foreground", "#e5e5e5")),
            foreground_dim: parse_scss_color(&theme_color(cfg, "foregroundDim", "#a3a3a3")),
            on_critical: parse_scss_color(&theme_color(cfg, "onCritical", "#ffffff")),
            on_primary: parse_scss_color(&theme_color(cfg, "onPrimary", "#0b0f17")),
            outline: parse_scss_color(&theme_color(cfg, "outline", "#334155")),
            primary: parse_scss_color(&theme_color(cfg, "primary", "#60a5fa")),
            success: parse_scss_color(&theme_color(cfg, "success", "#22c55e")),
            surface: parse_scss_color(&theme_color(cfg, "surface", "#111827")),
            surface_active: parse_scss_color(&theme_color(cfg, "surfaceActive", "#1f2937")),
            surface_container: parse_scss_color(&theme_color(cfg, "surfaceContainer", "#172033")),
            surface_hover: parse_scss_color(&theme_color(cfg, "surfaceHover", "#243044")),
            warning: parse_scss_color(&theme_color(cfg, "warning", "#f97316")),
        }
    }
}

pub fn parse_scss_color(value: &str) -> Color {
    let value = value.trim();
    if let Some(color) = parse_hex(value) {
        return color;
    }
    if let Some(color) = parse_rgba(value) {
        return color;
    }
    Color::WHITE
}

pub fn battery_ring_color(class: &str, palette: Palette) -> Color {
    if class.contains("critical") {
        color_hex("#ef4444")
    } else if class.contains("low") {
        color_hex("#f97316")
    } else if class.contains("medium") {
        color_hex("#eab308")
    } else if class.contains("good") {
        color_hex("#22c55e")
    } else if class.contains("charging") {
        palette.primary
    } else {
        color_hex("#06b6d4")
    }
}

fn update_device(vars: &Vars, prefix: &str, device: &mut DeviceAudio) {
    update_u8(vars, &format!("{prefix}_value"), &mut device.value);
    update_string(vars, &format!("{prefix}_percent"), &mut device.percent);
    update_path(vars, &format!("{prefix}_icon"), &mut device.icon);
    update_string(vars, &format!("{prefix}_text"), &mut device.text);
    update_color(vars, &format!("{prefix}_color"), &mut device.color);
    update_string(vars, &format!("{prefix}_class"), &mut device.class);
    update_string(vars, &format!("{prefix}_device"), &mut device.device);
}

fn update_string(vars: &Vars, key: &str, target: &mut String) {
    if let Some(value) = vars.get(key) {
        target.clone_from(value);
    }
}

fn update_path(vars: &Vars, key: &str, target: &mut PathBuf) {
    if let Some(value) = vars.get(key) {
        *target = PathBuf::from(value);
    }
}

fn update_color(vars: &Vars, key: &str, target: &mut Color) {
    if let Some(value) = vars.get(key) {
        *target = parse_scss_color(value);
    }
}

fn update_bool(vars: &Vars, key: &str, target: &mut bool) {
    if let Some(value) = vars.get(key) {
        *target = value == "on" || value == "true" || value == "1";
    }
}

fn update_f32(vars: &Vars, key: &str, target: &mut f32) {
    if let Some(value) = vars.get(key).and_then(|value| value.parse::<f32>().ok()) {
        *target = value;
    }
}

fn update_u32(vars: &Vars, key: &str, target: &mut u32) {
    if let Some(value) = vars.get(key).and_then(|value| value.parse::<u32>().ok()) {
        *target = value;
    }
}

fn update_u8(vars: &Vars, key: &str, target: &mut u8) {
    if let Some(value) = vars.get(key).and_then(|value| value.parse::<u8>().ok()) {
        *target = value;
    }
}

fn parse_hex(value: &str) -> Option<Color> {
    let hex = value.strip_prefix('#')?;
    let (r, g, b, a) = match hex.len() {
        6 => (
            u8::from_str_radix(&hex[0..2], 16).ok()?,
            u8::from_str_radix(&hex[2..4], 16).ok()?,
            u8::from_str_radix(&hex[4..6], 16).ok()?,
            255,
        ),
        8 => (
            u8::from_str_radix(&hex[0..2], 16).ok()?,
            u8::from_str_radix(&hex[2..4], 16).ok()?,
            u8::from_str_radix(&hex[4..6], 16).ok()?,
            u8::from_str_radix(&hex[6..8], 16).ok()?,
        ),
        _ => return None,
    };
    Some(Color::from_rgba8(r, g, b, f32::from(a) / 255.0))
}

fn parse_rgba(value: &str) -> Option<Color> {
    let body = value
        .strip_prefix("rgba(")
        .or_else(|| value.strip_prefix("rgb("))?
        .trim_end_matches(')');
    let mut parts = body.split(',').map(str::trim);
    let r = parts.next()?.parse::<u8>().ok()?;
    let g = parts.next()?.parse::<u8>().ok()?;
    let b = parts.next()?.parse::<u8>().ok()?;
    let a = parts
        .next()
        .and_then(|value| value.parse::<f32>().ok())
        .unwrap_or(1.0)
        .clamp(0.0, 1.0);
    Some(Color::from_rgba8(r, g, b, a))
}

fn color_hex(value: &str) -> Color {
    parse_hex(value).unwrap_or(Color::WHITE)
}
