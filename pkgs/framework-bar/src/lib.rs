use std::{
    collections::{BTreeMap, HashMap, HashSet},
    env,
    ffi::OsStr,
    fs::{self, File, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
    process::Command as ProcessCommand,
    sync::Arc,
    time::Instant,
};

use anyhow::{Context, Result, anyhow};
use chrono::{Datelike, Local, Timelike};
use clap::{Subcommand, ValueEnum};
use fs2::FileExt;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use walkdir::WalkDir;

pub type Vars = BTreeMap<String, String>;
pub const NOTIFICATION_PREVIEW_CHARS: usize = 96;
pub mod ipc;
pub mod native_app;
pub mod state;
pub mod systray;

pub mod config {
    pub use super::{CommandPaths, Config, Icons, read_config};
}

pub mod helpers {
    pub use super::{
        command, output, runtime_dir, sanitize_id, status, value_bool, value_string, value_u64,
    };
}

pub mod icons {
    pub use super::{
        IconResolver, best_icon_match, cache_key, data_dirs, find_icon_name, icon_file_matches,
        icon_rank, icon_themes, read_desktop_key,
    };
}

pub mod collect {
    pub use super::{NOTIFICATION_PREVIEW_CHARS, Vars};

    pub mod niri {
        pub use super::super::{
            NiriGroup, NiriSnapshot, NiriWindow, NiriWorkspace, build_window, build_workspace,
            niri_event_affects_bar, niri_json, niri_snapshot, niri_vars, output_names,
            window_order, window_workspace_id, workspace_label, workspace_output,
        };
    }

    pub mod audio {
        pub use super::super::{
            AudioDevice, AudioState, audio_device_state, audio_event_affects_bar, audio_target,
            audio_vars, format_audio_set_value, parse_device_description, parse_volume,
            run_audio_command, split_wpctl_property,
        };
    }

    pub mod battery {
        pub use super::super::{
            battery_device, battery_event_affects_bar, battery_unknown_vars, battery_vars,
            daemon_on_battery, display_device, parse_colon_field, tlp_mode, upower_field,
        };
    }

    pub mod brightness {
        pub use super::super::{
            brightness_vars, format_brightness_set_value, parse_brightness_machine,
            run_brightness_command,
        };
    }

    pub mod perf {
        pub use super::super::{
            CpuSample, NetSample, PerfSampler, cpu_percent, format_rate, gpu_percent,
            network_interface, network_rates, perf_vars, ram_percent, read_u64,
        };
    }

    pub mod media {
        pub use super::super::{media_vars, run_media_command};
    }

    pub mod network {
        pub use super::super::{
            cc_bt_state, cc_dark_state, cc_dnd_state, cc_toggle, cc_wifi_state, network_vars,
            parse_active_wifi_signal, parse_nmcli_field, toggle_state_vars, unescape_nmcli,
            wifi_connect, wifi_disconnect, wifi_rescan, wifi_scan, wifi_vars,
        };
    }

    pub mod datetime {
        pub use super::super::datetime_vars;
    }

    pub mod theme {
        pub use super::super::{theme_color, theme_vars};
    }

    pub mod notifications {
        pub use super::super::{
            MakoNotification, NotificationLock, NotificationRow, NotificationState, cap_text,
            mako_history_ids, mako_notifications, notification_action, notification_mark_read,
            notification_mark_unread, notification_preview, notification_row, notification_rows,
            notification_state, notification_vars, parse_mako_history_ids,
            run_notification_command,
        };
    }
}

#[derive(Debug, Subcommand)]
pub enum AudioCommand {
    Volume {
        device: AudioDevice,
        direction: VolumeDirection,
        #[arg(long, default_value_t = 0.025)]
        step: f32,
    },
    Toggle {
        device: AudioDevice,
    },
    Set {
        device: AudioDevice,
        value: f32,
    },
}

#[derive(Debug, Subcommand)]
pub enum BrightnessCommand {
    Set { value: f32 },
}

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum AudioDevice {
    Speaker,
    Mic,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum VolumeDirection {
    Up,
    Down,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum MediaAction {
    PlayPause,
    Stop,
    Previous,
    Next,
}

#[derive(Debug, Subcommand)]
pub enum NotificationCommand {
    Action,
    MarkRead { id: Option<String> },
    MarkUnread { id: Option<String> },
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Config {
    pub home: PathBuf,
    pub preferred_interface: Option<String>,
    pub commands: CommandPaths,
    pub icons: Icons,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CommandPaths {
    pub niri: PathBuf,
    pub wpctl: PathBuf,
    pub pactl: PathBuf,
    pub upower: PathBuf,
    pub tlp_stat: PathBuf,
    pub playerctl: PathBuf,
    pub brightnessctl: PathBuf,
    pub nmcli: PathBuf,
    pub makoctl: PathBuf,
    pub pavucontrol: PathBuf,
    pub systemctl: PathBuf,
    #[serde(default)]
    pub bluetoothctl: PathBuf,
    #[serde(default)]
    pub darkman: PathBuf,
    #[serde(default)]
    pub overskride: PathBuf,
    #[serde(default)]
    pub grep: PathBuf,
    #[serde(default)]
    pub jq: PathBuf,
    #[serde(default)]
    pub awk: PathBuf,
    #[serde(default)]
    pub lock_screen: PathBuf,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Icons {
    pub app_placeholder: PathBuf,
    pub battery_ac: PathBuf,
    pub battery_bat: PathBuf,
    #[serde(default)]
    pub battery_charging: PathBuf,
    #[serde(default)]
    pub battery_normal: PathBuf,
    pub battery_unknown: PathBuf,
    #[serde(default)]
    pub brightness: PathBuf,
    #[serde(default)]
    pub control_center: PathBuf,
    #[serde(default)]
    pub media: PathBuf,
    #[serde(default)]
    pub network: PathBuf,
    pub mic_active: PathBuf,
    pub mic_muted: PathBuf,
    #[serde(default)]
    pub notification: PathBuf,
    pub speaker_high: PathBuf,
    pub speaker_low: PathBuf,
    pub speaker_muted: PathBuf,
    #[serde(default)]
    pub tray: PathBuf,
    #[serde(default)]
    pub bluetooth: PathBuf,
    #[serde(default)]
    pub clear: PathBuf,
    #[serde(default)]
    pub dark_mode: PathBuf,
    #[serde(default)]
    pub lock: PathBuf,
    #[serde(default)]
    pub logout: PathBuf,
    #[serde(default)]
    pub reboot: PathBuf,
    #[serde(default)]
    pub shutdown: PathBuf,
    #[serde(default)]
    pub suspend: PathBuf,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NiriGroup {
    pub monitor: String,
    pub workspaces: Vec<NiriWorkspace>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NiriWorkspace {
    pub label: String,
    pub windows: Vec<NiriWindow>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NiriWindow {
    pub id: u64,
    pub title: String,
    pub focused: bool,
    pub icon_path: String,
}

#[derive(Debug, Clone)]
pub struct NiriSnapshot {
    pub groups: Vec<NiriGroup>,
    pub outputs: Vec<String>,
}

#[derive(Debug, Clone, Copy)]
pub struct CpuSample {
    pub total: u64,
    pub idle: u64,
}

#[derive(Debug, Clone, Copy)]
pub struct NetSample {
    pub time: Instant,
    pub rx: u64,
    pub tx: u64,
}

#[derive(Debug, Default)]
pub struct PerfSampler {
    pub cpu: Option<CpuSample>,
    pub net: Option<NetSample>,
}

pub struct IconResolver {
    cfg: Arc<Config>,
    cache_dir: PathBuf,
    memory: HashMap<String, PathBuf>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct MakoNotification {
    pub id: u64,
    #[serde(default)]
    pub app_name: Option<String>,
    #[serde(default)]
    pub desktop_entry: Option<String>,
    #[serde(default)]
    pub summary: String,
    #[serde(default)]
    pub body: String,
    #[serde(default)]
    pub urgency: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct NotificationRow {
    pub key: String,
    pub id: String,
    pub source: String,
    pub class: String,
    pub app: String,
    pub summary: String,
    pub preview: String,
    pub body: String,
    pub urgency: String,
    pub unread: bool,
}

pub fn read_config(path: &Path) -> Result<Config> {
    let text = fs::read_to_string(path)
        .with_context(|| format!("failed to read config {}", path.display()))?;
    serde_json::from_str(&text)
        .with_context(|| format!("failed to parse config {}", path.display()))
}

pub fn run_daemon(cfg: Arc<Config>) -> Result<()> {
    native_app::run(cfg)
}

pub fn niri_vars(cfg: &Arc<Config>, resolver: &mut IconResolver) -> Result<Vars> {
    let snapshot = niri_snapshot(cfg, resolver)?;
    let mut vars = Vars::new();
    vars.insert(
        "niri_groups".to_string(),
        serde_json::to_string(&snapshot.groups)?,
    );
    Ok(vars)
}

pub fn run_audio_command(cfg: &Arc<Config>, command: AudioCommand) -> Result<()> {
    match command {
        AudioCommand::Volume {
            device,
            direction,
            step,
        } => {
            let target = audio_target(device);
            let value = match direction {
                VolumeDirection::Up => format!("{step:.3}+"),
                VolumeDirection::Down => format!("{step:.3}-"),
            };
            let mut args = vec!["set-volume", target, value.as_str()];
            if matches!(direction, VolumeDirection::Up) {
                args.extend(["-l", "1.0"]);
            }
            status(cfg, &cfg.commands.wpctl, args)?;
        }
        AudioCommand::Toggle { device } => {
            status(
                cfg,
                &cfg.commands.wpctl,
                ["set-mute", audio_target(device), "toggle"],
            )?;
        }
        AudioCommand::Set { device, value } => {
            let value = format_audio_set_value(value);
            status(
                cfg,
                &cfg.commands.wpctl,
                ["set-volume", audio_target(device), value.as_str()],
            )?;
        }
    }

    Ok(())
}

pub fn run_brightness_command(cfg: &Arc<Config>, command: BrightnessCommand) -> Result<()> {
    match command {
        BrightnessCommand::Set { value } => {
            let value = format_brightness_set_value(value);
            status(
                cfg,
                &cfg.commands.brightnessctl,
                ["--class=backlight", "set", value.as_str()],
            )?;
        }
    }

    Ok(())
}

pub fn run_media_command(cfg: &Arc<Config>, action: MediaAction) -> Result<()> {
    let action = match action {
        MediaAction::PlayPause => "play-pause",
        MediaAction::Stop => "stop",
        MediaAction::Previous => "previous",
        MediaAction::Next => "next",
    };
    let _ = status(cfg, &cfg.commands.playerctl, [action]);
    Ok(())
}

pub fn run_notification_command(cfg: &Arc<Config>, command: NotificationCommand) -> Result<()> {
    match command {
        NotificationCommand::Action => notification_action(cfg),
        NotificationCommand::MarkRead { id } => {
            if let Some(id) = id.or_else(|| env::var("id").ok()) {
                notification_mark_read(cfg, &id)
            } else {
                Ok(())
            }
        }
        NotificationCommand::MarkUnread { id } => {
            if let Some(id) = id.or_else(|| env::var("id").ok()) {
                notification_mark_unread(cfg, &id)
            } else {
                Ok(())
            }
        }
    }
}

pub fn niri_snapshot(cfg: &Arc<Config>, resolver: &mut IconResolver) -> Result<NiriSnapshot> {
    let windows = niri_json(cfg, "windows", Value::Array(Vec::new()))?;
    let workspaces = niri_json(cfg, "workspaces", Value::Array(Vec::new()))?;
    let outputs = niri_json(cfg, "outputs", Value::Object(Default::default()))?;

    let windows = windows.as_array().cloned().unwrap_or_default();
    let workspaces = workspaces.as_array().cloned().unwrap_or_default();
    let mut monitors = output_names(&outputs);

    if monitors.is_empty() {
        monitors = workspaces
            .iter()
            .filter_map(workspace_output)
            .filter(|output| !output.is_empty())
            .collect();
        monitors.sort();
        monitors.dedup();
    }

    let groups = monitors
        .iter()
        .map(|monitor| {
            let workspaces = workspaces
                .iter()
                .filter(|workspace| {
                    workspace_output(workspace).as_deref() == Some(monitor.as_str())
                })
                .filter(|workspace| {
                    value_bool(workspace, &["is_active", "active", "is_focused", "focused"])
                })
                .map(|workspace| build_workspace(workspace, &windows, resolver))
                .collect::<Vec<_>>();

            NiriGroup {
                monitor: monitor.clone(),
                workspaces,
            }
        })
        .collect();

    Ok(NiriSnapshot {
        groups,
        outputs: monitors,
    })
}

pub fn niri_json(cfg: &Config, message: &str, fallback: Value) -> Result<Value> {
    match output(cfg, &cfg.commands.niri, ["msg", "-j", message])? {
        Some(text) => serde_json::from_str(&text)
            .with_context(|| format!("failed to parse niri {message} JSON")),
        None => Ok(fallback),
    }
}

pub fn build_workspace(
    workspace: &Value,
    windows: &[Value],
    resolver: &mut IconResolver,
) -> NiriWorkspace {
    let workspace_id = value_u64(workspace, &["id"]);
    let mut window_values = windows
        .iter()
        .filter(|window| window_workspace_id(window) == workspace_id)
        .collect::<Vec<_>>();

    window_values.sort_by_key(|window| {
        (
            window_order(Some(window)).unwrap_or((999_999_999, 999_999_999)),
            value_u64(window, &["id"]).unwrap_or(u64::MAX),
        )
    });
    let windows = window_values
        .into_iter()
        .filter_map(|window| build_window(window, resolver))
        .collect::<Vec<_>>();

    NiriWorkspace {
        label: workspace_label(workspace),
        windows,
    }
}

pub fn build_window(window: &Value, resolver: &mut IconResolver) -> Option<NiriWindow> {
    let id = value_u64(window, &["id"])?;
    let app_id = value_string(window, &["app_id"]).unwrap_or_default();
    let title = value_string(window, &["title"])
        .or_else(|| (!app_id.is_empty()).then_some(app_id.clone()))
        .unwrap_or_else(|| "Desktop".to_string());
    let icon_path = resolver.resolve(&app_id, &title).display().to_string();

    Some(NiriWindow {
        id,
        title,
        focused: value_bool(window, &["is_focused", "focused"]),
        icon_path,
    })
}

pub fn workspace_label(workspace: &Value) -> String {
    value_string(workspace, &["name"])
        .or_else(|| value_u64(workspace, &["idx"]).map(|value| value.to_string()))
        .or_else(|| value_u64(workspace, &["index"]).map(|value| value.to_string()))
        .or_else(|| value_u64(workspace, &["id"]).map(|value| value.to_string()))
        .unwrap_or_else(|| "?".to_string())
}

pub fn workspace_output(workspace: &Value) -> Option<String> {
    value_string(workspace, &["output", "output_name", "monitor"])
}

pub fn window_workspace_id(window: &Value) -> Option<u64> {
    value_u64(window, &["workspace_id", "workspace"])
}

pub fn window_order(window: Option<&Value>) -> Option<(i64, i64)> {
    let window = window?;
    let position = window
        .pointer("/layout/pos_in_scrolling_layout")
        .or_else(|| window.pointer("/layout/tile_pos_in_workspace_view"))?;
    let position = position.as_array()?;
    Some((
        position
            .first()
            .and_then(Value::as_i64)
            .unwrap_or(999_999_999),
        position
            .get(1)
            .and_then(Value::as_i64)
            .unwrap_or(999_999_999),
    ))
}

pub fn output_names(outputs: &Value) -> Vec<String> {
    let mut names = match outputs {
        Value::Array(outputs) => outputs
            .iter()
            .filter_map(|output| value_string(output, &["name", "output"]))
            .collect::<Vec<_>>(),
        Value::Object(outputs) => outputs.keys().cloned().collect::<Vec<_>>(),
        _ => Vec::new(),
    };
    names.sort();
    names.dedup();
    names
}

pub fn niri_event_affects_bar(event: &str) -> bool {
    [
        "{\"WorkspacesChanged\":",
        "{\"WindowOpenedOrChanged\":",
        "{\"WindowsChanged\":",
        "{\"WindowClosed\":",
        "{\"WindowFocusChanged\":",
        "{\"WindowLayoutsChanged\":",
        "{\"WorkspaceActivated\":",
        "{\"OutputsChanged\":",
        "{\"Output",
    ]
    .iter()
    .any(|prefix| event.starts_with(prefix))
}

pub fn audio_vars(cfg: &Config) -> Result<Vars> {
    let foreground = theme_color(cfg, "foreground", "#e5e5e5");
    let foreground_dim = theme_color(cfg, "foregroundDim", "#a3a3a3");
    let speaker = audio_device_state(cfg, AudioDevice::Speaker)?;
    let mic = audio_device_state(cfg, AudioDevice::Mic)?;

    let mut vars = Vars::new();
    let (speaker_icon, speaker_color, speaker_class, speaker_text) = if speaker.muted {
        (
            cfg.icons.speaker_muted.display().to_string(),
            foreground_dim.clone(),
            "audio-control speaker muted".to_string(),
            format!("Output muted ({}%) - {}", speaker.value, speaker.device),
        )
    } else if speaker.value == 0 {
        (
            cfg.icons.speaker_muted.display().to_string(),
            foreground_dim.clone(),
            "audio-control speaker".to_string(),
            format!("Output 0% - {}", speaker.device),
        )
    } else if speaker.value < 45 {
        (
            cfg.icons.speaker_low.display().to_string(),
            foreground.clone(),
            "audio-control speaker".to_string(),
            format!("Output {}% - {}", speaker.value, speaker.device),
        )
    } else {
        (
            cfg.icons.speaker_high.display().to_string(),
            foreground.clone(),
            "audio-control speaker".to_string(),
            format!("Output {}% - {}", speaker.value, speaker.device),
        )
    };

    let (mic_icon, mic_color, mic_class, mic_text) = if mic.muted {
        (
            cfg.icons.mic_muted.display().to_string(),
            foreground_dim,
            "audio-control mic muted".to_string(),
            format!("Input muted ({}%) - {}", mic.value, mic.device),
        )
    } else if mic.value == 0 {
        (
            cfg.icons.mic_muted.display().to_string(),
            theme_color(cfg, "foregroundDim", "#a3a3a3"),
            "audio-control mic".to_string(),
            format!("Input 0% - {}", mic.device),
        )
    } else {
        (
            cfg.icons.mic_active.display().to_string(),
            foreground,
            "audio-control mic".to_string(),
            format!("Input {}% - {}", mic.value, mic.device),
        )
    };

    vars.insert("audio_speaker_value".to_string(), speaker.value.to_string());
    vars.insert(
        "audio_speaker_percent".to_string(),
        format!("{}%", speaker.value),
    );
    vars.insert("audio_speaker_class".to_string(), speaker_class);
    vars.insert("audio_speaker_icon".to_string(), speaker_icon);
    vars.insert("audio_speaker_text".to_string(), speaker_text);
    vars.insert("audio_speaker_color".to_string(), speaker_color);
    vars.insert("audio_speaker_device".to_string(), speaker.device);
    vars.insert("audio_mic_value".to_string(), mic.value.to_string());
    vars.insert("audio_mic_percent".to_string(), format!("{}%", mic.value));
    vars.insert("audio_mic_class".to_string(), mic_class);
    vars.insert("audio_mic_icon".to_string(), mic_icon);
    vars.insert("audio_mic_text".to_string(), mic_text);
    vars.insert("audio_mic_color".to_string(), mic_color);
    vars.insert("audio_mic_device".to_string(), mic.device);
    Ok(vars)
}

#[derive(Debug)]
pub struct AudioState {
    pub value: u8,
    pub muted: bool,
    pub device: String,
}

pub fn audio_device_state(cfg: &Config, device: AudioDevice) -> Result<AudioState> {
    let target = audio_target(device);
    let volume_output = output(cfg, &cfg.commands.wpctl, ["get-volume", target])?
        .unwrap_or_else(|| "Volume: 0 [MUTED]".to_string());
    let (value, muted) = parse_volume(&volume_output);
    let device_name = output(cfg, &cfg.commands.wpctl, ["inspect", target])?
        .and_then(|text| parse_device_description(&text))
        .unwrap_or_else(|| match device {
            AudioDevice::Speaker => "Unknown output".to_string(),
            AudioDevice::Mic => "Unknown input".to_string(),
        });

    Ok(AudioState {
        value,
        muted,
        device: device_name,
    })
}

pub fn audio_target(device: AudioDevice) -> &'static str {
    match device {
        AudioDevice::Speaker => "@DEFAULT_AUDIO_SINK@",
        AudioDevice::Mic => "@DEFAULT_AUDIO_SOURCE@",
    }
}

pub fn parse_volume(text: &str) -> (u8, bool) {
    let muted = text.contains("MUTED");
    let value = text
        .split_whitespace()
        .skip_while(|part| *part != "Volume:")
        .nth(1)
        .and_then(|part| part.parse::<f64>().ok())
        .map(|volume| (volume * 100.0).round().clamp(0.0, 100.0) as u8)
        .unwrap_or(0);
    (value, muted)
}

pub fn parse_device_description(text: &str) -> Option<String> {
    let mut fallback = None;
    for line in text.lines() {
        if let Some(value) = split_wpctl_property(line, "node.description") {
            return Some(value);
        }
        if fallback.is_none() {
            fallback = split_wpctl_property(line, "node.name");
        }
    }
    fallback
}

pub fn split_wpctl_property(line: &str, key: &str) -> Option<String> {
    let (line_key, value) = line.split_once(" = ")?;
    if !line_key.trim().ends_with(key) {
        return None;
    }
    Some(value.trim().trim_matches('"').to_string())
}

pub fn audio_event_affects_bar(event: &str) -> bool {
    event.contains(" on card")
        || event.contains(" on server")
        || event.contains(" on sink")
        || event.contains(" on source")
}

pub fn battery_vars(cfg: &Config) -> Result<Vars> {
    let foreground = theme_color(cfg, "foreground", "#e5e5e5");
    let device = display_device(cfg)?.or_else(|| battery_device(cfg).ok().flatten());

    let Some(device) = device else {
        return Ok(battery_unknown_vars(cfg, &foreground));
    };

    let percentage = upower_field(cfg, &device, "percentage")?;
    let Some(percentage) = percentage else {
        return Ok(battery_unknown_vars(cfg, &foreground));
    };

    let capacity = percentage
        .trim_end_matches('%')
        .split('.')
        .next()
        .and_then(|value| value.parse::<i64>().ok())
        .unwrap_or(0)
        .clamp(0, 100);
    let state = upower_field(cfg, &device, "state")?.unwrap_or_default();
    let on_battery = daemon_on_battery(cfg)?.unwrap_or_default();
    let mode = tlp_mode(cfg)?.unwrap_or_default();

    let mut class = "island battery".to_string();
    let mut icon = cfg.icons.battery_unknown.display().to_string();
    let mut profile = "Unknown".to_string();

    match mode.as_str() {
        "AC" => {
            icon = cfg.icons.battery_ac.display().to_string();
            profile = "AC".to_string();
        }
        "BAT" => {
            icon = cfg.icons.battery_bat.display().to_string();
            profile = "Battery".to_string();
        }
        _ if state == "charging" || state == "fully-charged" || on_battery == "no" => {
            icon = cfg.icons.battery_ac.display().to_string();
            profile = "AC".to_string();
        }
        _ if on_battery == "yes" => {
            icon = cfg.icons.battery_bat.display().to_string();
            profile = "Battery".to_string();
        }
        _ => {}
    }

    if state == "charging" || state == "fully-charged" || mode == "AC" || on_battery == "no" {
        class.push_str(" charging");
    } else if capacity < 10 {
        class.push_str(" critical");
    } else if capacity < 30 {
        class.push_str(" low");
    } else if capacity < 50 {
        class.push_str(" medium");
    } else if capacity < 80 {
        class.push_str(" good");
    } else {
        class.push_str(" full");
    }

    let mut vars = Vars::new();
    vars.insert("battery_value".to_string(), capacity.to_string());
    vars.insert(
        "battery_tooltip".to_string(),
        format!("{percentage} - {profile} profile"),
    );
    vars.insert("battery_class".to_string(), class);
    vars.insert("battery_icon".to_string(), icon);
    vars.insert("battery_color".to_string(), foreground);
    Ok(vars)
}

pub fn battery_unknown_vars(cfg: &Config, foreground: &str) -> Vars {
    let mut vars = Vars::new();
    vars.insert("battery_value".to_string(), "0".to_string());
    vars.insert("battery_tooltip".to_string(), "Battery --".to_string());
    vars.insert(
        "battery_class".to_string(),
        "island battery unknown".to_string(),
    );
    vars.insert(
        "battery_icon".to_string(),
        cfg.icons.battery_unknown.display().to_string(),
    );
    vars.insert("battery_color".to_string(), foreground.to_string());
    vars
}

pub fn display_device(cfg: &Config) -> Result<Option<String>> {
    let devices = output(cfg, &cfg.commands.upower, ["--enumerate"])?.unwrap_or_default();
    Ok(devices
        .lines()
        .find(|line| line.ends_with("DisplayDevice"))
        .map(str::to_string))
}

pub fn battery_device(cfg: &Config) -> Result<Option<String>> {
    let devices = output(cfg, &cfg.commands.upower, ["--enumerate"])?.unwrap_or_default();
    Ok(devices
        .lines()
        .find(|line| line.contains("/battery_"))
        .map(str::to_string))
}

pub fn upower_field(cfg: &Config, device: &str, field: &str) -> Result<Option<String>> {
    let info = output(cfg, &cfg.commands.upower, ["--show-info", device])?.unwrap_or_default();
    Ok(parse_colon_field(&info, field))
}

pub fn daemon_on_battery(cfg: &Config) -> Result<Option<String>> {
    let dump = output(cfg, &cfg.commands.upower, ["--dump"])?.unwrap_or_default();
    Ok(parse_colon_field(&dump, "on-battery"))
}

pub fn tlp_mode(cfg: &Config) -> Result<Option<String>> {
    let status = output(cfg, &cfg.commands.tlp_stat, ["-s"])?.unwrap_or_default();
    for line in status.lines() {
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        if key.trim() == "Mode" {
            return Ok(Some(value.trim().to_string()));
        }
    }
    Ok(None)
}

pub fn parse_colon_field(text: &str, field: &str) -> Option<String> {
    for line in text.lines() {
        let Some((key, value)) = line.split_once(':') else {
            continue;
        };
        if key.trim() == field {
            return Some(value.trim().to_string());
        }
    }
    None
}

pub fn battery_event_affects_bar(event: &str) -> bool {
    event.contains("device changed:")
        || event.contains("device added:")
        || event.contains("device removed:")
        || event.contains("daemon changed:")
}

pub fn brightness_vars(cfg: &Config) -> Result<Vars> {
    let value = output(
        cfg,
        &cfg.commands.brightnessctl,
        ["--class=backlight", "--machine-readable", "info"],
    )?
    .and_then(|text| parse_brightness_machine(&text))
    .unwrap_or(0);

    let mut vars = Vars::new();
    vars.insert("brightness_value".to_string(), value.to_string());
    vars.insert("brightness_text".to_string(), format!("{value}%"));
    Ok(vars)
}

pub fn parse_brightness_machine(text: &str) -> Option<u8> {
    text.split(',')
        .nth(3)?
        .trim()
        .trim_end_matches('%')
        .parse::<f64>()
        .ok()
        .map(|value| value.round().clamp(0.0, 100.0) as u8)
}

pub fn format_audio_set_value(value: f32) -> String {
    format!("{:.3}", value.clamp(0.0, 100.0) / 100.0)
}

pub fn format_brightness_set_value(value: f32) -> String {
    format!("{}%", value.round().clamp(1.0, 100.0) as u8)
}

pub fn perf_vars(cfg: &Config, sampler: &mut PerfSampler) -> Result<Vars> {
    let iface = network_interface(cfg);
    let (up, down) = network_rates(&iface, sampler);
    let ram = ram_percent().unwrap_or_else(|| "--".to_string());
    let cpu = cpu_percent(sampler).unwrap_or_else(|| "--".to_string());
    let gpu = gpu_percent().unwrap_or_else(|| "--".to_string());

    let mut vars = Vars::new();
    vars.insert("perf_cpu".to_string(), cpu);
    vars.insert("perf_ram".to_string(), ram);
    vars.insert("perf_gpu".to_string(), gpu);
    vars.insert("perf_up".to_string(), up);
    vars.insert("perf_down".to_string(), down);
    Ok(vars)
}

pub fn network_interface(cfg: &Config) -> String {
    if let Some(preferred) = &cfg.preferred_interface
        && Path::new("/sys/class/net").join(preferred).is_dir()
    {
        return preferred.clone();
    }

    fs::read_dir("/sys/class/net")
        .ok()
        .into_iter()
        .flatten()
        .filter_map(|entry| entry.ok())
        .filter_map(|entry| entry.file_name().into_string().ok())
        .find(|name| name != "lo")
        .unwrap_or_else(|| "lo".to_string())
}

pub fn network_rates(iface: &str, sampler: &mut PerfSampler) -> (String, String) {
    let rx = read_u64(
        Path::new("/sys/class/net")
            .join(iface)
            .join("statistics/rx_bytes"),
    )
    .unwrap_or(0);
    let tx = read_u64(
        Path::new("/sys/class/net")
            .join(iface)
            .join("statistics/tx_bytes"),
    )
    .unwrap_or(0);
    let now = Instant::now();
    let current = NetSample { time: now, rx, tx };
    let previous = sampler.net.replace(current).unwrap_or(current);
    let elapsed = now.duration_since(previous.time).as_secs().max(1);
    let down = rx.saturating_sub(previous.rx) / 1024 / elapsed;
    let up = tx.saturating_sub(previous.tx) / 1024 / elapsed;
    (format_rate(up), format_rate(down))
}

pub fn network_vars(cfg: &Config) -> Result<Vars> {
    let iface = network_interface(cfg);
    let device = output(
        cfg,
        &cfg.commands.nmcli,
        [
            "-t",
            "-f",
            "GENERAL.STATE,GENERAL.CONNECTION",
            "dev",
            "show",
            iface.as_str(),
        ],
    )?
    .unwrap_or_default();
    let state = parse_nmcli_field(&device, "GENERAL.STATE").unwrap_or_default();
    let connection = parse_nmcli_field(&device, "GENERAL.CONNECTION").unwrap_or_default();
    let signal = output(
        cfg,
        &cfg.commands.nmcli,
        [
            "-t",
            "-f",
            "ACTIVE,SSID,SIGNAL",
            "dev",
            "wifi",
            "list",
            "--rescan",
            "no",
        ],
    )?
    .and_then(|text| parse_active_wifi_signal(&text));

    let connected = state.starts_with("100");
    let label = if connected && !connection.is_empty() && connection != "--" {
        connection
    } else if connected {
        iface.clone()
    } else {
        "Disconnected".to_string()
    };
    let detail = match signal {
        Some(signal) if connected => format!("Wi-Fi {signal}%"),
        _ if connected => "Connected".to_string(),
        _ => "Offline".to_string(),
    };
    let class = if connected {
        "cc-tile network connected"
    } else {
        "cc-tile network disconnected"
    };

    let mut vars = Vars::new();
    vars.insert("network_label".to_string(), label);
    vars.insert("network_detail".to_string(), detail);
    vars.insert("network_class".to_string(), class.to_string());
    Ok(vars)
}

pub fn toggle_state_vars(cfg: &Config) -> Vars {
    let mut vars = Vars::new();
    vars.insert("cc_wifi".to_string(), bool_state(cc_wifi_state(cfg)));
    vars.insert("cc_bt".to_string(), bool_state(cc_bt_state(cfg)));
    vars.insert("cc_dnd".to_string(), bool_state(cc_dnd_state(cfg)));
    vars.insert("cc_dark".to_string(), bool_state(cc_dark_state(cfg)));
    vars
}

pub fn wifi_vars(cfg: &Config) -> Vars {
    let mut vars = Vars::new();
    let networks = wifi_scan(cfg).unwrap_or_default();
    vars.insert(
        "wifi_networks".to_string(),
        serde_json::to_string(&networks).unwrap_or_else(|_| "[]".to_string()),
    );
    vars
}

pub fn cc_wifi_state(cfg: &Config) -> bool {
    output(cfg, &cfg.commands.nmcli, ["-t", "radio", "wifi"])
        .ok()
        .flatten()
        .is_some_and(|state| state.trim() == "enabled")
}

pub fn cc_bt_state(cfg: &Config) -> bool {
    output(cfg, &cfg.commands.bluetoothctl, ["show"])
        .ok()
        .flatten()
        .is_some_and(|state| state.lines().any(|line| line.trim() == "Powered: yes"))
}

pub fn cc_dnd_state(cfg: &Config) -> bool {
    output(cfg, &cfg.commands.makoctl, ["mode"])
        .ok()
        .flatten()
        .is_some_and(|state| state.contains("do-not-disturb"))
}

pub fn cc_dark_state(cfg: &Config) -> bool {
    output(cfg, &cfg.commands.darkman, ["get"])
        .ok()
        .flatten()
        .is_some_and(|state| state.trim() == "dark")
}

pub fn cc_toggle(cfg: &Config, target: &str) -> Result<()> {
    match target {
        "wifi" => {
            let state = if cc_wifi_state(cfg) { "off" } else { "on" };
            status(cfg, &cfg.commands.nmcli, ["radio", "wifi", state])
        }
        "bt" => {
            let state = if cc_bt_state(cfg) { "off" } else { "on" };
            status(cfg, &cfg.commands.bluetoothctl, ["power", state])
        }
        "dnd" => status(cfg, &cfg.commands.makoctl, ["mode", "-t", "do-not-disturb"]),
        "dark" => status(cfg, &cfg.commands.darkman, ["toggle"]),
        _ => Ok(()),
    }
}

pub fn wifi_scan(cfg: &Config) -> Result<Vec<crate::state::WifiNetwork>> {
    use std::collections::BTreeMap;

    let known = output(
        cfg,
        &cfg.commands.nmcli,
        ["-t", "-f", "NAME", "connection", "show"],
    )?
    .unwrap_or_default()
    .lines()
    .map(str::to_string)
    .collect::<HashSet<_>>();
    let text = output(
        cfg,
        &cfg.commands.nmcli,
        [
            "-m",
            "multiline",
            "-f",
            "ACTIVE,SIGNAL,SECURITY,SSID",
            "device",
            "wifi",
            "list",
        ],
    )?
    .unwrap_or_default();
    let mut networks = BTreeMap::<String, crate::state::WifiNetwork>::new();
    let mut active = false;
    let mut signal = 0_i64;
    let mut security = String::new();

    for line in text.lines() {
        if let Some(value) = line.strip_prefix("ACTIVE:") {
            active = value.trim() == "yes";
        } else if let Some(value) = line.strip_prefix("SIGNAL:") {
            signal = value.trim().parse::<i64>().unwrap_or(0);
        } else if let Some(value) = line.strip_prefix("SECURITY:") {
            let value = value.trim();
            security = if value == "--" {
                String::new()
            } else {
                value.to_string()
            };
        } else if let Some(value) = line.strip_prefix("SSID:") {
            let ssid = value.trim();
            if ssid.is_empty() || ssid == "--" {
                active = false;
                signal = 0;
                security.clear();
                continue;
            }
            let entry =
                networks
                    .entry(ssid.to_string())
                    .or_insert_with(|| crate::state::WifiNetwork {
                        active,
                        signal,
                        security: security.clone(),
                        ssid: ssid.to_string(),
                        known: known.contains(ssid),
                    });
            entry.active |= active;
            if signal > entry.signal {
                entry.signal = signal;
                entry.security.clone_from(&security);
            }
            entry.known |= known.contains(ssid);
            active = false;
            signal = 0;
            security.clear();
        }
    }

    let mut networks = networks.into_values().collect::<Vec<_>>();
    networks.sort_by(|left, right| {
        left.active
            .cmp(&right.active)
            .reverse()
            .then_with(|| right.signal.cmp(&left.signal))
            .then_with(|| left.ssid.cmp(&right.ssid))
    });
    Ok(networks)
}

pub fn wifi_rescan(cfg: &Config) -> Result<()> {
    let _ = status(cfg, &cfg.commands.nmcli, ["device", "wifi", "rescan"]);
    Ok(())
}

pub fn wifi_connect(cfg: &Config, ssid: &str, password: &str) -> Result<()> {
    if ssid.is_empty() {
        return Ok(());
    }
    let known = output(
        cfg,
        &cfg.commands.nmcli,
        ["-t", "-f", "NAME", "connection", "show"],
    )?
    .unwrap_or_default()
    .lines()
    .any(|name| name == ssid);
    if known {
        let _ = status(cfg, &cfg.commands.nmcli, ["connection", "up", "id", ssid]);
    } else if password.is_empty() {
        let _ = status(
            cfg,
            &cfg.commands.nmcli,
            ["device", "wifi", "connect", ssid],
        );
    } else {
        let _ = status(
            cfg,
            &cfg.commands.nmcli,
            ["device", "wifi", "connect", ssid, "password", password],
        );
    }
    Ok(())
}

pub fn wifi_disconnect(cfg: &Config) -> Result<()> {
    let devices = output(
        cfg,
        &cfg.commands.nmcli,
        ["-t", "-f", "DEVICE,TYPE", "device"],
    )?
    .unwrap_or_default();
    if let Some(device) = devices.lines().find_map(|line| {
        let (device, kind) = line.split_once(':')?;
        (kind == "wifi").then_some(device)
    }) {
        let _ = status(cfg, &cfg.commands.nmcli, ["device", "disconnect", device]);
    }
    Ok(())
}

fn bool_state(value: bool) -> String {
    if value { "on" } else { "off" }.to_string()
}

pub fn parse_nmcli_field(text: &str, field: &str) -> Option<String> {
    text.lines().find_map(|line| {
        let (key, value) = line.split_once(':')?;
        (key == field).then(|| unescape_nmcli(value))
    })
}

pub fn parse_active_wifi_signal(text: &str) -> Option<u8> {
    text.lines().find_map(|line| {
        let mut fields = line.split(':');
        let active = fields.next()?;
        let _ssid = fields.next()?;
        let signal = fields.next()?;
        (active == "yes")
            .then(|| signal.parse::<u8>().ok())
            .flatten()
    })
}

pub fn unescape_nmcli(value: &str) -> String {
    value.replace("\\:", ":").replace("\\\\", "\\")
}

pub fn ram_percent() -> Option<String> {
    let meminfo = fs::read_to_string("/proc/meminfo").ok()?;
    let mut total = None;
    let mut available = None;
    for line in meminfo.lines() {
        if line.starts_with("MemTotal:") {
            total = line
                .split_whitespace()
                .nth(1)
                .and_then(|value| value.parse::<u64>().ok());
        } else if line.starts_with("MemAvailable:") {
            available = line
                .split_whitespace()
                .nth(1)
                .and_then(|value| value.parse::<u64>().ok());
        }
    }
    let total = total?;
    let available = available?;
    ((total - available) * 100)
        .checked_div(total)
        .map(|percent| format!("{percent}%"))
}

pub fn cpu_percent(sampler: &mut PerfSampler) -> Option<String> {
    let stat = fs::read_to_string("/proc/stat").ok()?;
    let cpu_line = stat.lines().find(|line| line.starts_with("cpu "))?;
    let fields = cpu_line
        .split_whitespace()
        .skip(1)
        .filter_map(|value| value.parse::<u64>().ok())
        .collect::<Vec<_>>();
    if fields.len() < 8 {
        return None;
    }

    let idle = fields[3] + fields[4];
    let total = fields.iter().take(8).sum::<u64>();
    let current = CpuSample { total, idle };
    let previous = sampler.cpu.replace(current)?;
    let total_delta = total.saturating_sub(previous.total);
    let idle_delta = idle.saturating_sub(previous.idle);
    (total_delta != 0).then(|| format!("{}%", (100 * (total_delta - idle_delta)) / total_delta))
}

pub fn gpu_percent() -> Option<String> {
    [
        "/sys/class/drm/card1/device/gpu_busy_percent",
        "/sys/class/drm/card0/device/gpu_busy_percent",
    ]
    .iter()
    .find_map(|path| read_u64(path).map(|value| format!("{value}%")))
}

pub fn read_u64(path: impl AsRef<Path>) -> Option<u64> {
    fs::read_to_string(path).ok()?.trim().parse().ok()
}

pub fn format_rate(value: u64) -> String {
    if value >= 1024 {
        format!("{:.1}M", value as f64 / 1024.0)
    } else {
        format!("{value}K")
    }
}

pub fn media_vars(cfg: &Config) -> Result<Vars> {
    let status = output(cfg, &cfg.commands.playerctl, ["status"])?;
    let text = if let Some(status) = status {
        let metadata = output(
            cfg,
            &cfg.commands.playerctl,
            ["metadata", "--format", "{{artist}} - {{title}}"],
        )?
        .unwrap_or_default();
        if metadata.is_empty() || metadata == " - " {
            status
        } else {
            metadata
        }
    } else {
        String::new()
    };

    let mut vars = Vars::new();
    vars.insert("media_text".to_string(), text);
    Ok(vars)
}

pub fn datetime_vars() -> Vars {
    let now = Local::now();
    let weekday = match now.weekday().number_from_monday() {
        1 => "\u{4e00}",
        2 => "\u{4e8c}",
        3 => "\u{4e09}",
        4 => "\u{56db}",
        5 => "\u{4e94}",
        6 => "\u{516d}",
        _ => "\u{65e5}",
    };
    let mut vars = Vars::new();
    vars.insert(
        "datetime_date".to_string(),
        format!("{:02}/{:02} {}", now.month(), now.day(), weekday),
    );
    vars.insert(
        "datetime_time".to_string(),
        format!("{:02}:{:02}", now.hour(), now.minute()),
    );
    vars
}

pub fn theme_vars(cfg: &Config) -> Vars {
    let mut vars = Vars::new();
    vars.insert(
        "cc_icon".to_string(),
        theme_color(cfg, "foreground", "#e5e5e5"),
    );
    vars.insert(
        "cc_accent".to_string(),
        theme_color(cfg, "primary", "#60a5fa"),
    );
    vars.insert(
        "cc_on_accent".to_string(),
        theme_color(cfg, "onPrimary", "#0b0f17"),
    );
    vars
}

pub fn notification_vars(cfg: &Config, prune: bool) -> Result<Vars> {
    let foreground = theme_color(cfg, "foreground", "#e5e5e5");
    let critical = theme_color(cfg, "critical", "#ef4444");
    let active_notifications = mako_notifications(cfg, "list").unwrap_or_default();
    let history_notifications = mako_notifications(cfg, "history").unwrap_or_default();
    let state = notification_state()?;
    let _guard = state.lock()?;

    if prune {
        let history_ids = active_notifications
            .iter()
            .chain(history_notifications.iter())
            .map(|notification| notification.id.to_string())
            .collect::<Vec<_>>();
        let unread = state.read_unread()?;
        let retained = unread
            .into_iter()
            .filter(|id| history_ids.iter().any(|history_id| history_id == id))
            .collect::<Vec<_>>();
        state.write_unread(&retained)?;
    }

    let unread = state.read_unread()?;
    let count = unread.len();
    let label = if count > 99 {
        "99+".to_string()
    } else {
        count.to_string()
    };
    let mut class = "island notifications".to_string();
    let mut color = foreground;
    if count > 0 {
        class.push_str(" active");
        color = critical;
    }

    let rows = notification_rows(&active_notifications, &history_notifications, &unread);
    let mut vars = Vars::new();
    vars.insert("notifications_count".to_string(), count.to_string());
    vars.insert("notifications_label".to_string(), label);
    vars.insert("notifications_class".to_string(), class);
    vars.insert("notifications_color".to_string(), color);
    vars.insert(
        "notifications_history_count".to_string(),
        rows.len().to_string(),
    );
    vars.insert(
        "notifications_history".to_string(),
        serde_json::to_string(&rows)?,
    );
    Ok(vars)
}

pub fn mako_notifications(cfg: &Config, command_name: &str) -> Result<Vec<MakoNotification>> {
    let text = output(cfg, &cfg.commands.makoctl, [command_name, "-j"])?.unwrap_or_default();
    if text.trim().is_empty() {
        Ok(Vec::new())
    } else {
        serde_json::from_str(&text)
            .with_context(|| format!("failed to parse makoctl {command_name} JSON"))
    }
}

pub fn notification_rows(
    active: &[MakoNotification],
    history: &[MakoNotification],
    unread: &[String],
) -> Vec<NotificationRow> {
    let unread = unread.iter().cloned().collect::<HashSet<_>>();
    let mut seen = HashSet::new();
    let mut rows = Vec::new();

    for (source, notifications) in [("active", active), ("history", history)] {
        for notification in notifications {
            if !seen.insert(notification.id) {
                continue;
            }
            if rows.len() >= 6 {
                return rows;
            }
            rows.push(notification_row(notification, source, &unread));
        }
    }

    rows
}

pub fn notification_row(
    notification: &MakoNotification,
    source: &str,
    unread: &HashSet<String>,
) -> NotificationRow {
    let id = notification.id.to_string();
    let app = notification
        .app_name
        .as_deref()
        .filter(|value| !value.is_empty())
        .or(notification.desktop_entry.as_deref())
        .filter(|value| !value.is_empty())
        .unwrap_or("Notification")
        .to_string();
    let summary = if notification.summary.trim().is_empty() {
        app.clone()
    } else {
        notification.summary.trim().to_string()
    };
    let body = notification
        .body
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    let preview = notification_preview(&body);
    let urgency = if notification.urgency.trim().is_empty() {
        "normal".to_string()
    } else {
        notification.urgency.trim().to_string()
    };

    let mut class = format!("cc-notification-row {source} {urgency}");
    let is_unread = unread.contains(&id);
    if is_unread {
        class.push_str(" unread");
    }

    NotificationRow {
        key: format!("{source}-{id}"),
        id,
        source: source.to_string(),
        class,
        app,
        summary,
        preview,
        body,
        urgency,
        unread: is_unread,
    }
}

pub fn notification_preview(body: &str) -> String {
    if body.is_empty() {
        return "No details".to_string();
    }

    cap_text(body, NOTIFICATION_PREVIEW_CHARS)
}

pub fn cap_text(text: &str, max_chars: usize) -> String {
    let mut iter = text.chars();
    let preview = iter.by_ref().take(max_chars).collect::<String>();
    if iter.next().is_some() {
        format!("{preview}...")
    } else {
        preview
    }
}

pub struct NotificationState {
    pub unread_file: PathBuf,
    pub lock_file: PathBuf,
}

pub struct NotificationLock {
    pub file: File,
}

impl Drop for NotificationLock {
    fn drop(&mut self) {
        let _ = self.file.unlock();
    }
}

impl NotificationState {
    fn lock(&self) -> Result<NotificationLock> {
        let file = OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(&self.lock_file)?;
        file.lock_exclusive()?;
        Ok(NotificationLock { file })
    }

    fn read_unread(&self) -> Result<Vec<String>> {
        let text = fs::read_to_string(&self.unread_file).unwrap_or_default();
        let mut ids = text
            .lines()
            .map(str::trim)
            .filter(|line| !line.is_empty())
            .map(str::to_string)
            .collect::<Vec<_>>();
        ids.sort_by_key(|id| id.parse::<u64>().unwrap_or(u64::MAX));
        ids.dedup();
        Ok(ids)
    }

    fn write_unread(&self, ids: &[String]) -> Result<()> {
        let tmp = self.unread_file.with_extension("tmp");
        {
            let mut file = File::create(&tmp)?;
            for id in ids {
                writeln!(file, "{id}")?;
            }
        }
        fs::rename(tmp, &self.unread_file)?;
        Ok(())
    }
}

pub fn notification_state() -> Result<NotificationState> {
    let dir = runtime_dir().join("framework-bar-notifications");
    fs::create_dir_all(&dir)?;
    let unread_file = dir.join("unread");
    let lock_file = dir.join("unread.lock");
    OpenOptions::new()
        .create(true)
        .append(true)
        .open(&unread_file)?;
    Ok(NotificationState {
        unread_file,
        lock_file,
    })
}

pub fn notification_mark_read(cfg: &Config, id: &str) -> Result<()> {
    let _ = cfg;
    let state = notification_state()?;
    let _guard = state.lock()?;
    let ids = state
        .read_unread()?
        .into_iter()
        .filter(|unread_id| unread_id != id)
        .collect::<Vec<_>>();
    state.write_unread(&ids)
}

pub fn notification_mark_unread(cfg: &Config, id: &str) -> Result<()> {
    let _ = cfg;
    let state = notification_state()?;
    let _guard = state.lock()?;
    let mut ids = state
        .read_unread()?
        .into_iter()
        .filter(|unread_id| unread_id != id)
        .collect::<Vec<_>>();
    ids.push(id.to_string());
    ids.sort_by_key(|id| id.parse::<u64>().unwrap_or(u64::MAX));
    ids.dedup();
    state.write_unread(&ids)
}

pub fn notification_action(cfg: &Config) -> Result<()> {
    loop {
        let state = notification_state()?;
        let guard = state.lock()?;
        let history = mako_history_ids(cfg)?;
        let restore_id = history.first().cloned();
        let unread = state.read_unread()?;
        let has_unread = unread
            .iter()
            .any(|id| history.iter().any(|history_id| history_id == id));
        let restore_is_unread = restore_id
            .as_ref()
            .is_some_and(|restore_id| unread.iter().any(|id| id == restore_id));
        drop(guard);

        if !has_unread {
            break;
        }
        let Some(restore_id) = restore_id else {
            break;
        };

        if status(cfg, &cfg.commands.makoctl, ["restore"]).is_err() {
            break;
        }

        if restore_is_unread {
            notification_mark_read(cfg, &restore_id)?;
        }
    }

    Ok(())
}

pub fn mako_history_ids(cfg: &Config) -> Result<Vec<String>> {
    let history = output(cfg, &cfg.commands.makoctl, ["history"])?.unwrap_or_default();
    Ok(parse_mako_history_ids(&history))
}

pub fn parse_mako_history_ids(text: &str) -> Vec<String> {
    text.lines()
        .filter_map(|line| {
            let line = line.trim();
            let rest = line.strip_prefix("Notification ")?;
            let id = rest.split_once(':')?.0;
            (!id.is_empty()).then_some(id.to_string())
        })
        .collect()
}

impl IconResolver {
    fn new(cfg: Arc<Config>) -> Self {
        let cache_dir = runtime_dir().join("framework-bar-icon-cache");
        let _ = fs::create_dir_all(&cache_dir);
        Self {
            cfg,
            cache_dir,
            memory: HashMap::new(),
        }
    }

    fn resolve(&mut self, app_id: &str, title: &str) -> PathBuf {
        let key = if app_id.is_empty() {
            format!("title:{title}")
        } else {
            format!("app:{app_id}")
        };

        if let Some(path) = self.memory.get(&key) {
            return path.clone();
        }

        let cache_file = self.cache_dir.join(cache_key(&key));
        if let Ok(path) = fs::read_to_string(&cache_file) {
            let path = PathBuf::from(path.trim());
            if path == self.cfg.icons.app_placeholder || path.exists() {
                self.memory.insert(key, path.clone());
                return path;
            }
        }

        let path = self
            .resolve_uncached(app_id, title)
            .unwrap_or_else(|| self.cfg.icons.app_placeholder.clone());
        let _ = fs::write(&cache_file, path.display().to_string());
        self.memory.insert(key, path.clone());
        path
    }

    fn resolve_icon_name(&mut self, name: &str) -> Option<PathBuf> {
        let key = format!("icon:{name}");
        if let Some(path) = self.memory.get(&key) {
            return (path.exists()).then(|| path.clone());
        }

        let cache_file = self.cache_dir.join(cache_key(&key));
        if let Ok(path) = fs::read_to_string(&cache_file) {
            let path = PathBuf::from(path.trim());
            if path.exists() {
                self.memory.insert(key, path.clone());
                return Some(path);
            }
        }

        let mut icon_dirs = Vec::new();
        for data_dir in data_dirs(&self.cfg.home) {
            icon_dirs.push(data_dir.join("icons"));
            icon_dirs.push(data_dir.join("pixmaps"));
        }
        let path = find_icon_name(name, &icon_dirs, &icon_themes(&self.cfg.home))?;
        let _ = fs::write(&cache_file, path.display().to_string());
        self.memory.insert(key, path.clone());
        Some(path)
    }

    fn resolve_uncached(&self, app_id: &str, title: &str) -> Option<PathBuf> {
        let app_lc = app_id.to_lowercase();
        let title_lc = title.to_lowercase();
        let data_dirs = data_dirs(&self.cfg.home);
        let mut icon = None;
        let mut desktop_root = None;

        'desktop: for data_dir in &data_dirs {
            let apps_dir = data_dir.join("applications");
            if !apps_dir.is_dir() {
                continue;
            }

            for entry in WalkDir::new(&apps_dir)
                .follow_links(true)
                .into_iter()
                .filter_map(|entry| entry.ok())
            {
                let path = entry.path();
                if !path.is_file() || path.extension() != Some(OsStr::new("desktop")) {
                    continue;
                }

                let stem = path
                    .file_stem()
                    .and_then(OsStr::to_str)
                    .unwrap_or_default()
                    .to_lowercase();
                let startup = read_desktop_key(path, "StartupWMClass")
                    .unwrap_or_default()
                    .to_lowercase();
                let exec = read_desktop_key(path, "Exec")
                    .unwrap_or_default()
                    .to_lowercase();

                let mut matched = false;
                if !app_lc.is_empty() {
                    matched = stem == app_lc
                        || startup == app_lc
                        || exec.contains(&app_lc)
                        || (!stem.is_empty() && app_lc.contains(&stem));
                }
                if !matched && !title_lc.is_empty() {
                    matched = (!stem.is_empty() && title_lc.contains(&stem))
                        || (!startup.is_empty() && title_lc.contains(&startup));
                }

                if matched {
                    icon = read_desktop_key(path, "Icon");
                    desktop_root = path.parent().and_then(Path::parent).map(Path::to_path_buf);
                    break 'desktop;
                }
            }
        }

        let icon = icon?;
        let mut icon_dirs = Vec::new();
        if let Some(desktop_root) = desktop_root {
            icon_dirs.push(desktop_root.join("icons"));
            icon_dirs.push(desktop_root.join("pixmaps"));
        }
        for data_dir in data_dirs {
            icon_dirs.push(data_dir.join("icons"));
            icon_dirs.push(data_dir.join("pixmaps"));
        }

        find_icon_name(&icon, &icon_dirs, &icon_themes(&self.cfg.home))
    }
}

pub fn data_dirs(home: &Path) -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    dirs.push(home.join(".local/share"));
    if let Some(xdg_dirs) = env::var_os("XDG_DATA_DIRS") {
        dirs.extend(env::split_paths(&xdg_dirs));
    }
    dirs.extend(
        [
            "/run/current-system/sw/share",
            "/etc/profiles/per-user/iceice666/share",
            "/usr/local/share",
            "/usr/share",
        ]
        .into_iter()
        .map(PathBuf::from),
    );
    dirs.sort();
    dirs.dedup();
    dirs
}

pub fn icon_themes(home: &Path) -> Vec<&'static str> {
    let active_theme = fs::read_link(home.join(".config/eww/theme.scss"))
        .ok()
        .map(|path| path.display().to_string())
        .unwrap_or_default();
    if active_theme.contains("light") {
        vec!["Papirus", "Papirus-Dark", "hicolor", "Adwaita"]
    } else {
        vec!["Papirus-Dark", "Papirus", "hicolor", "Adwaita"]
    }
}

pub fn read_desktop_key(path: &Path, wanted: &str) -> Option<String> {
    let text = fs::read_to_string(path).ok()?;
    let mut in_entry = false;
    for line in text.lines() {
        if line.starts_with('[') {
            in_entry = line == "[Desktop Entry]";
            continue;
        }
        if !in_entry {
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        if key == wanted {
            return Some(value.to_string());
        }
    }
    None
}

pub fn find_icon_name(icon: &str, dirs: &[PathBuf], themes: &[&str]) -> Option<PathBuf> {
    let icon_path = Path::new(icon);
    if icon_path.is_absolute() {
        return icon_path.exists().then(|| icon_path.to_path_buf());
    }

    for base in dirs {
        if !base.is_dir() {
            continue;
        }

        for theme in themes {
            let theme_dir = base.join(theme);
            if let Some(path) = best_icon_match(icon, &theme_dir, None) {
                return Some(path);
            }
        }

        if let Some(path) = best_icon_match(icon, base, Some(3)) {
            return Some(path);
        }
    }

    None
}

pub fn best_icon_match(icon: &str, root: &Path, max_depth: Option<usize>) -> Option<PathBuf> {
    if !root.is_dir() {
        return None;
    }

    let mut walk = WalkDir::new(root).follow_links(true);
    if let Some(max_depth) = max_depth {
        walk = walk.max_depth(max_depth);
    }

    let mut matches = walk
        .into_iter()
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.into_path())
        .filter(|path| path.is_file())
        .filter(|path| icon_file_matches(icon, path))
        .collect::<Vec<_>>();

    matches.sort_by_key(|path| (icon_rank(path), path.display().to_string()));
    matches.into_iter().next()
}

pub fn icon_file_matches(icon: &str, path: &Path) -> bool {
    let Some(file_name) = path.file_name().and_then(OsStr::to_str) else {
        return false;
    };
    file_name == icon
        || file_name == format!("{icon}.png")
        || file_name == format!("{icon}.svg")
        || file_name == format!("{icon}.xpm")
}

pub fn icon_rank(path: &Path) -> u8 {
    let path = path.display().to_string();
    if path.contains("/24x24/") {
        0
    } else if path.contains("/32x32/") {
        1
    } else if path.contains("/48x48/") {
        2
    } else if path.contains("/scalable/") {
        3
    } else if path.ends_with(".png") {
        4
    } else if path.ends_with(".svg") {
        5
    } else {
        6
    }
}

pub fn cache_key(value: &str) -> String {
    let digest = Sha256::digest(value.as_bytes());
    digest.iter().map(|byte| format!("{byte:02x}")).collect()
}

pub fn theme_color(cfg: &Config, name: &str, fallback: &str) -> String {
    let theme_file = cfg.home.join(".config/eww/theme.scss");
    let Ok(text) = fs::read_to_string(theme_file) else {
        return fallback.to_string();
    };
    let wanted = format!("${name}");
    for line in text.lines() {
        let Some((key, value)) = line.split_once(':') else {
            continue;
        };
        if key.trim() == wanted {
            return value
                .split(';')
                .next()
                .unwrap_or(fallback)
                .trim()
                .to_string();
        }
    }
    fallback.to_string()
}

pub fn command(cfg: &Config, program: &Path) -> ProcessCommand {
    let mut cmd = ProcessCommand::new(program);
    cmd.env("HOME", &cfg.home);
    cmd.env("XDG_CONFIG_HOME", cfg.home.join(".config"));
    cmd
}

pub fn output<I, S>(cfg: &Config, program: &Path, args: I) -> Result<Option<String>>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let output = command(cfg, program).args(args).output()?;
    if !output.status.success() {
        return Ok(None);
    }
    Ok(Some(
        String::from_utf8_lossy(&output.stdout)
            .trim_end_matches(['\n', '\r'])
            .to_string(),
    ))
}

pub fn status<I, S>(cfg: &Config, program: &Path, args: I) -> Result<()>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let status = command(cfg, program).args(args).status()?;
    if status.success() {
        Ok(())
    } else {
        Err(anyhow!(
            "command {} failed with {status}",
            program.display()
        ))
    }
}

pub fn value_string(value: &Value, names: &[&str]) -> Option<String> {
    names
        .iter()
        .find_map(|name| value.get(*name).and_then(Value::as_str).map(str::to_string))
}

pub fn value_u64(value: &Value, names: &[&str]) -> Option<u64> {
    names.iter().find_map(|name| {
        let value = value.get(*name)?;
        value
            .as_u64()
            .or_else(|| value.as_str().and_then(|value| value.parse().ok()))
    })
}

pub fn value_bool(value: &Value, names: &[&str]) -> bool {
    names
        .iter()
        .any(|name| value.get(*name).and_then(Value::as_bool).unwrap_or(false))
}

pub fn runtime_dir() -> PathBuf {
    env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"))
}

pub fn sanitize_id(value: &str) -> String {
    value
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || ch == '_' {
                ch
            } else {
                '_'
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_volume() {
        assert_eq!(parse_volume("Volume: 0.42"), (42, false));
        assert_eq!(parse_volume("Volume: 0.715 [MUTED]"), (72, true));
        assert_eq!(parse_volume("Volume: 2.0"), (100, false));
    }

    #[test]
    fn formats_audio_and_brightness_set_values() {
        assert_eq!(format_audio_set_value(42.0), "0.420");
        assert_eq!(format_audio_set_value(150.0), "1.000");
        assert_eq!(format_brightness_set_value(0.0), "1%");
        assert_eq!(format_brightness_set_value(92.4), "92%");
    }

    #[test]
    fn parses_brightness_machine_output() {
        assert_eq!(
            parse_brightness_machine("amdgpu_bl1,backlight,60295,92%,65535"),
            Some(92)
        );
    }

    #[test]
    fn parses_wpctl_description_with_fallback() {
        let text = r#"
            node.name = "alsa_output"
            node.description = "Built-in Audio"
        "#;
        assert_eq!(
            parse_device_description(text).as_deref(),
            Some("Built-in Audio")
        );

        let text = r#"node.name = "alsa_input""#;
        assert_eq!(
            parse_device_description(text).as_deref(),
            Some("alsa_input")
        );
    }

    #[test]
    fn parses_colon_fields() {
        let text = "  percentage:          87%\n  state:               discharging\n";
        assert_eq!(
            parse_colon_field(text, "percentage").as_deref(),
            Some("87%")
        );
        assert_eq!(
            parse_colon_field(text, "state").as_deref(),
            Some("discharging")
        );
    }

    #[test]
    fn formats_rates() {
        assert_eq!(format_rate(0), "0K");
        assert_eq!(format_rate(999), "999K");
        assert_eq!(format_rate(1536), "1.5M");
    }

    #[test]
    fn parses_mako_history() {
        let text = "Notification 42:\n  App name: test\nNotification 100:\n";
        assert_eq!(parse_mako_history_ids(text), vec!["42", "100"]);
    }

    #[test]
    fn parses_mako_json_history() {
        let text = r#"[{"id":42,"app_name":"Ghostty","summary":"Build","body":"Done","urgency":"normal"}]"#;
        let notifications = serde_json::from_str::<Vec<MakoNotification>>(text).unwrap();
        assert_eq!(notifications[0].id, 42);
        assert_eq!(notifications[0].app_name.as_deref(), Some("Ghostty"));
        assert_eq!(notifications[0].summary, "Build");
    }

    #[test]
    fn builds_notification_rows_active_first() {
        let active = vec![MakoNotification {
            id: 2,
            app_name: Some("Chat".to_string()),
            desktop_entry: None,
            summary: "Message".to_string(),
            body: "hello\nthere".to_string(),
            urgency: "normal".to_string(),
        }];
        let history = vec![
            MakoNotification {
                id: 2,
                app_name: Some("Chat".to_string()),
                desktop_entry: None,
                summary: "Message".to_string(),
                body: "duplicate".to_string(),
                urgency: "normal".to_string(),
            },
            MakoNotification {
                id: 1,
                app_name: None,
                desktop_entry: Some("app.desktop".to_string()),
                summary: String::new(),
                body: "old".to_string(),
                urgency: String::new(),
            },
        ];
        let rows = notification_rows(&active, &history, &["2".to_string()]);
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].key, "active-2");
        assert!(rows[0].class.contains("unread"));
        assert_eq!(rows[0].body, "hello there");
        assert_eq!(rows[0].preview, "hello there");
        assert_eq!(rows[1].summary, "app.desktop");
    }

    #[test]
    fn caps_notification_preview() {
        assert_eq!(notification_preview(""), "No details");
        assert_eq!(cap_text("hello", 8), "hello");
        assert_eq!(cap_text("hello world", 5), "hello...");
    }

    #[test]
    fn parses_network_fields() {
        let text = "GENERAL.STATE:100 (connected)\nGENERAL.CONNECTION:yee\\:lab\n";
        assert_eq!(
            parse_nmcli_field(text, "GENERAL.CONNECTION").as_deref(),
            Some("yee:lab")
        );
        assert_eq!(
            parse_active_wifi_signal("no:other:40\nyes:yee:95").as_ref(),
            Some(&95)
        );
    }

    #[test]
    fn sanitizes_bar_ids() {
        assert_eq!(sanitize_id("eDP-1"), "eDP_1");
        assert_eq!(sanitize_id("HDMI A 1"), "HDMI_A_1");
    }
}
