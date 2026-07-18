use std::{
    collections::{BTreeMap, HashMap, HashSet},
    env,
    ffi::OsStr,
    fs::{self, File, OpenOptions},
    io::{BufRead, BufReader, Write},
    path::{Path, PathBuf},
    process::{Command as ProcessCommand, Stdio},
    sync::{Arc, mpsc},
    thread,
    time::{Duration, Instant},
};

use anyhow::{Context, Result, anyhow};
use chrono::{Datelike, Local, Timelike};
use clap::{Parser, Subcommand, ValueEnum};
use fs2::FileExt;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use walkdir::WalkDir;

type Vars = BTreeMap<String, String>;
const FORCE_RESYNC_VAR: &str = "__force_resync";
const NOTIFICATION_PREVIEW_CHARS: usize = 96;

#[derive(Debug, Parser)]
struct Cli {
    #[arg(long)]
    config_file: PathBuf,

    #[command(subcommand)]
    command: CliCommand,
}

#[derive(Debug, Subcommand)]
enum CliCommand {
    Daemon,
    Reload,
    SeedNiriGroups,
    Refresh {
        domain: RefreshDomain,
    },
    FocusWindow {
        id: String,
    },
    OpenPavucontrol,
    Audio {
        #[command(subcommand)]
        command: AudioCommand,
    },
    Brightness {
        #[command(subcommand)]
        command: BrightnessCommand,
    },
    Media {
        action: MediaAction,
    },
    Notifications {
        #[command(subcommand)]
        command: NotificationCommand,
    },
}

#[derive(Debug, Clone, Copy, ValueEnum)]
enum RefreshDomain {
    All,
    Niri,
    Audio,
    Battery,
    Brightness,
    Perf,
    Media,
    Datetime,
    Network,
    Notifications,
}

#[derive(Debug, Subcommand)]
enum AudioCommand {
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
enum BrightnessCommand {
    Set { value: f32 },
}

#[derive(Debug, Clone, Copy, ValueEnum)]
enum AudioDevice {
    Speaker,
    Mic,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
enum VolumeDirection {
    Up,
    Down,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
enum MediaAction {
    PlayPause,
    Stop,
    Previous,
    Next,
}

#[derive(Debug, Subcommand)]
enum NotificationCommand {
    Action,
    MarkRead { id: Option<String> },
    MarkUnread { id: Option<String> },
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Config {
    eww_config_dir: PathBuf,
    home: PathBuf,
    preferred_interface: Option<String>,
    commands: CommandPaths,
    icons: Icons,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CommandPaths {
    eww: PathBuf,
    niri: PathBuf,
    wpctl: PathBuf,
    pactl: PathBuf,
    upower: PathBuf,
    tlp_stat: PathBuf,
    playerctl: PathBuf,
    brightnessctl: PathBuf,
    nmcli: PathBuf,
    makoctl: PathBuf,
    pavucontrol: PathBuf,
    systemctl: PathBuf,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Icons {
    app_placeholder: PathBuf,
    battery_ac: PathBuf,
    battery_bat: PathBuf,
    battery_unknown: PathBuf,
    mic_active: PathBuf,
    mic_muted: PathBuf,
    speaker_high: PathBuf,
    speaker_low: PathBuf,
    speaker_muted: PathBuf,
}

#[derive(Debug, Serialize)]
struct NiriGroup {
    monitor: String,
    workspaces: Vec<NiriWorkspace>,
}

#[derive(Debug, Serialize)]
struct NiriWorkspace {
    label: String,
    windows: Vec<NiriWindow>,
}

#[derive(Debug, Serialize)]
struct NiriWindow {
    id: u64,
    title: String,
    focused: bool,
    icon_path: String,
}

#[derive(Debug)]
struct NiriSnapshot {
    groups: Vec<NiriGroup>,
    outputs: Vec<String>,
}

#[derive(Debug, Clone, Copy)]
struct CpuSample {
    total: u64,
    idle: u64,
}

#[derive(Debug, Clone, Copy)]
struct NetSample {
    time: Instant,
    rx: u64,
    tx: u64,
}

#[derive(Debug, Default)]
struct PerfSampler {
    cpu: Option<CpuSample>,
    net: Option<NetSample>,
}

struct IconResolver {
    cfg: Arc<Config>,
    cache_dir: PathBuf,
    memory: HashMap<String, PathBuf>,
}

#[derive(Debug, Deserialize)]
struct MakoNotification {
    id: u64,
    #[serde(default)]
    app_name: Option<String>,
    #[serde(default)]
    desktop_entry: Option<String>,
    #[serde(default)]
    summary: String,
    #[serde(default)]
    body: String,
    #[serde(default)]
    urgency: String,
}

#[derive(Debug, Serialize, PartialEq, Eq)]
struct NotificationRow {
    key: String,
    id: String,
    source: String,
    class: String,
    app: String,
    summary: String,
    preview: String,
    body: String,
    urgency: String,
    unread: bool,
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let cfg = Arc::new(read_config(&cli.config_file)?);

    match cli.command {
        CliCommand::Daemon => run_daemon(cfg),
        CliCommand::Reload => reload_eww(&cfg),
        CliCommand::SeedNiriGroups => seed_niri_groups(),
        CliCommand::Refresh { domain } => refresh_domain(&cfg, domain),
        CliCommand::FocusWindow { id } => {
            status(
                &cfg,
                &cfg.commands.niri,
                ["msg", "action", "focus-window", "--id", &id],
            )?;
            Ok(())
        }
        CliCommand::OpenPavucontrol => {
            command(&cfg, &cfg.commands.pavucontrol)
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()?;
            Ok(())
        }
        CliCommand::Audio { command } => run_audio_command(&cfg, command),
        CliCommand::Brightness { command } => run_brightness_command(&cfg, command),
        CliCommand::Media { action } => run_media_command(&cfg, action),
        CliCommand::Notifications { command } => run_notification_command(&cfg, command),
    }
}

fn seed_niri_groups() -> Result<()> {
    println!("[]");
    loop {
        thread::sleep(Duration::from_secs(3600));
    }
}

fn read_config(path: &Path) -> Result<Config> {
    let text = fs::read_to_string(path)
        .with_context(|| format!("failed to read config {}", path.display()))?;
    serde_json::from_str(&text)
        .with_context(|| format!("failed to parse config {}", path.display()))
}

fn run_daemon(cfg: Arc<Config>) -> Result<()> {
    wait_for_eww(&cfg)?;

    let (tx, rx) = mpsc::channel::<Vars>();
    spawn_niri_thread(cfg.clone(), tx.clone());
    spawn_audio_thread(cfg.clone(), tx.clone());
    spawn_battery_thread(cfg.clone(), tx.clone());
    spawn_brightness_thread(cfg.clone(), tx.clone());
    spawn_perf_thread(cfg.clone(), tx.clone());
    spawn_media_thread(cfg.clone(), tx.clone());
    spawn_network_thread(cfg.clone(), tx.clone());
    spawn_datetime_thread(tx.clone());
    spawn_theme_thread(cfg.clone(), tx.clone());
    spawn_notifications_thread(cfg.clone(), tx);

    update_loop(cfg, rx)
}

fn update_loop(cfg: Arc<Config>, rx: mpsc::Receiver<Vars>) -> Result<()> {
    let mut desired = Vars::new();
    let mut applied = Vars::new();
    let mut force_resync = false;

    loop {
        match rx.recv_timeout(Duration::from_millis(250)) {
            Ok(vars) => {
                force_resync |= merge_desired_vars(&mut desired, vars);
                while let Ok(vars) = rx.try_recv() {
                    force_resync |= merge_desired_vars(&mut desired, vars);
                }
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => return Ok(()),
        }

        if force_resync {
            applied.clear();
            force_resync = false;
        }

        let changed = desired
            .iter()
            .filter(|(name, value)| applied.get(*name) != Some(*value))
            .map(|(name, value)| (name.clone(), value.clone()))
            .collect::<Vars>();

        if changed.is_empty() {
            continue;
        }

        if !eww_ping(&cfg) {
            thread::sleep(Duration::from_millis(500));
            continue;
        }

        match eww_update(&cfg, &changed) {
            Ok(()) => applied.extend(changed),
            Err(error) => {
                eprintln!("failed to update eww variables: {error:#}");
                thread::sleep(Duration::from_millis(500));
            }
        }
    }
}

fn merge_desired_vars(desired: &mut Vars, mut vars: Vars) -> bool {
    let force_resync = vars.remove(FORCE_RESYNC_VAR).is_some();
    desired.extend(vars);
    force_resync
}

fn spawn_niri_thread(cfg: Arc<Config>, tx: mpsc::Sender<Vars>) {
    thread::spawn(move || {
        let mut resolver = IconResolver::new(cfg.clone());
        let mut last_outputs = Vec::<String>::new();

        loop {
            niri_refresh(&cfg, &tx, &mut resolver, &mut last_outputs);

            let (event_tx, event_rx) = mpsc::channel::<Option<String>>();
            start_niri_event_reader(cfg.clone(), event_tx);

            let mut dirty = false;
            let mut dirty_since = Instant::now();
            let mut last_snapshot = Instant::now();

            loop {
                match event_rx.recv_timeout(Duration::from_millis(100)) {
                    Ok(Some(event)) => {
                        if niri_event_affects_bar(&event) {
                            if !dirty {
                                dirty_since = Instant::now();
                            }
                            dirty = true;
                        }
                    }
                    Ok(None) | Err(mpsc::RecvTimeoutError::Disconnected) => break,
                    Err(mpsc::RecvTimeoutError::Timeout) => {}
                }

                if dirty && dirty_since.elapsed() >= Duration::from_millis(200) {
                    niri_refresh(&cfg, &tx, &mut resolver, &mut last_outputs);
                    dirty = false;
                    last_snapshot = Instant::now();
                } else if last_snapshot.elapsed() >= Duration::from_secs(30) {
                    niri_refresh(&cfg, &tx, &mut resolver, &mut last_outputs);
                    dirty = false;
                    last_snapshot = Instant::now();
                }
            }

            thread::sleep(Duration::from_millis(500));
        }
    });
}

fn start_niri_event_reader(cfg: Arc<Config>, tx: mpsc::Sender<Option<String>>) {
    thread::spawn(move || {
        let mut child = match command(&cfg, &cfg.commands.niri)
            .args(["msg", "-j", "event-stream"])
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
        {
            Ok(child) => child,
            Err(error) => {
                eprintln!("failed to start niri event stream: {error:#}");
                let _ = tx.send(None);
                return;
            }
        };

        if let Some(stdout) = child.stdout.take() {
            for line in BufReader::new(stdout).lines() {
                match line {
                    Ok(line) => {
                        if tx.send(Some(line)).is_err() {
                            break;
                        }
                    }
                    Err(error) => {
                        eprintln!("failed to read niri event stream: {error:#}");
                        break;
                    }
                }
            }
        }

        let _ = child.wait();
        let _ = tx.send(None);
    });
}

fn niri_refresh(
    cfg: &Arc<Config>,
    tx: &mpsc::Sender<Vars>,
    resolver: &mut IconResolver,
    last_outputs: &mut Vec<String>,
) {
    match niri_snapshot(cfg, resolver) {
        Ok(snapshot) => {
            let bars_reopened = open_bars_if_needed(cfg, &snapshot.outputs, last_outputs);
            if let Ok(groups) = serde_json::to_string(&snapshot.groups) {
                let mut vars = Vars::new();
                vars.insert("niri_groups".to_string(), groups);
                if bars_reopened {
                    vars.insert(FORCE_RESYNC_VAR.to_string(), "1".to_string());
                }
                send_vars(tx, vars);
            }
        }
        Err(error) => {
            eprintln!("failed to read niri state: {error:#}");
            let mut vars = Vars::new();
            vars.insert("niri_groups".to_string(), "[]".to_string());
            send_vars(tx, vars);
        }
    }
}

fn spawn_audio_thread(cfg: Arc<Config>, tx: mpsc::Sender<Vars>) {
    thread::spawn(move || {
        loop {
            send_result(&tx, audio_vars(&cfg));

            let mut child = match command(&cfg, &cfg.commands.pactl)
                .arg("subscribe")
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()
            {
                Ok(child) => child,
                Err(error) => {
                    eprintln!("failed to start pactl subscribe: {error:#}");
                    thread::sleep(Duration::from_secs(1));
                    continue;
                }
            };

            if let Some(stdout) = child.stdout.take() {
                for line in BufReader::new(stdout).lines() {
                    match line {
                        Ok(line) if audio_event_affects_bar(&line) => {
                            send_result(&tx, audio_vars(&cfg))
                        }
                        Ok(_) => {}
                        Err(error) => {
                            eprintln!("failed to read pactl subscribe: {error:#}");
                            break;
                        }
                    }
                }
            }

            let _ = child.wait();
            thread::sleep(Duration::from_secs(1));
        }
    });
}

fn spawn_battery_thread(cfg: Arc<Config>, tx: mpsc::Sender<Vars>) {
    thread::spawn(move || {
        loop {
            send_result(&tx, battery_vars(&cfg));

            let mut child = match command(&cfg, &cfg.commands.upower)
                .arg("--monitor")
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()
            {
                Ok(child) => child,
                Err(error) => {
                    eprintln!("failed to start upower monitor: {error:#}");
                    thread::sleep(Duration::from_secs(5));
                    continue;
                }
            };

            if let Some(stdout) = child.stdout.take() {
                for line in BufReader::new(stdout).lines() {
                    match line {
                        Ok(line) if battery_event_affects_bar(&line) => {
                            for delay in [
                                Duration::ZERO,
                                Duration::from_secs(1),
                                Duration::from_secs(1),
                                Duration::from_secs(3),
                                Duration::from_secs(5),
                                Duration::from_secs(20),
                                Duration::from_secs(30),
                            ] {
                                if !delay.is_zero() {
                                    thread::sleep(delay);
                                }
                                send_result(&tx, battery_vars(&cfg));
                            }
                        }
                        Ok(_) => {}
                        Err(error) => {
                            eprintln!("failed to read upower monitor: {error:#}");
                            break;
                        }
                    }
                }
            }

            let _ = child.wait();
            thread::sleep(Duration::from_secs(1));
        }
    });
}

fn spawn_brightness_thread(cfg: Arc<Config>, tx: mpsc::Sender<Vars>) {
    thread::spawn(move || {
        loop {
            send_result(&tx, brightness_vars(&cfg));
            thread::sleep(Duration::from_secs(2));
        }
    });
}

fn spawn_perf_thread(cfg: Arc<Config>, tx: mpsc::Sender<Vars>) {
    thread::spawn(move || {
        let mut sampler = PerfSampler::default();
        loop {
            send_result(&tx, perf_vars(&cfg, &mut sampler));
            thread::sleep(Duration::from_secs(1));
        }
    });
}

fn spawn_media_thread(cfg: Arc<Config>, tx: mpsc::Sender<Vars>) {
    thread::spawn(move || {
        loop {
            send_result(&tx, media_vars(&cfg));
            thread::sleep(Duration::from_secs(2));
        }
    });
}

fn spawn_network_thread(cfg: Arc<Config>, tx: mpsc::Sender<Vars>) {
    thread::spawn(move || {
        loop {
            send_result(&tx, network_vars(&cfg));
            thread::sleep(Duration::from_secs(10));
        }
    });
}

fn spawn_datetime_thread(tx: mpsc::Sender<Vars>) {
    thread::spawn(move || {
        loop {
            send_vars(&tx, datetime_vars());
            thread::sleep(Duration::from_secs(1));
        }
    });
}

fn spawn_theme_thread(cfg: Arc<Config>, tx: mpsc::Sender<Vars>) {
    thread::spawn(move || {
        loop {
            send_vars(&tx, theme_vars(&cfg));
            thread::sleep(Duration::from_secs(3));
        }
    });
}

fn spawn_notifications_thread(cfg: Arc<Config>, tx: mpsc::Sender<Vars>) {
    thread::spawn(move || {
        loop {
            send_result(&tx, notification_vars(&cfg, true));
            thread::sleep(Duration::from_secs(5));
        }
    });
}

fn send_result(tx: &mpsc::Sender<Vars>, vars: Result<Vars>) {
    match vars {
        Ok(vars) => send_vars(tx, vars),
        Err(error) => eprintln!("failed to collect eww state: {error:#}"),
    }
}

fn send_vars(tx: &mpsc::Sender<Vars>, vars: Vars) {
    let _ = tx.send(vars);
}

fn refresh_domain(cfg: &Arc<Config>, domain: RefreshDomain) -> Result<()> {
    let mut vars = Vars::new();

    match domain {
        RefreshDomain::All => {
            let mut sampler = PerfSampler::default();
            let mut resolver = IconResolver::new(cfg.clone());
            vars.extend(niri_vars(cfg, &mut resolver)?);
            vars.extend(audio_vars(cfg)?);
            vars.extend(battery_vars(cfg)?);
            vars.extend(brightness_vars(cfg)?);
            vars.extend(perf_vars(cfg, &mut sampler)?);
            vars.extend(media_vars(cfg)?);
            vars.extend(network_vars(cfg)?);
            vars.extend(datetime_vars());
            vars.extend(notification_vars(cfg, true)?);
        }
        RefreshDomain::Niri => {
            let mut resolver = IconResolver::new(cfg.clone());
            vars.extend(niri_vars(cfg, &mut resolver)?);
        }
        RefreshDomain::Audio => vars.extend(audio_vars(cfg)?),
        RefreshDomain::Battery => vars.extend(battery_vars(cfg)?),
        RefreshDomain::Brightness => vars.extend(brightness_vars(cfg)?),
        RefreshDomain::Perf => {
            let mut sampler = PerfSampler::default();
            vars.extend(perf_vars(cfg, &mut sampler)?);
        }
        RefreshDomain::Media => vars.extend(media_vars(cfg)?),
        RefreshDomain::Datetime => vars.extend(datetime_vars()),
        RefreshDomain::Network => vars.extend(network_vars(cfg)?),
        RefreshDomain::Notifications => vars.extend(notification_vars(cfg, true)?),
    }

    eww_update(cfg, &vars)
}

fn niri_vars(cfg: &Arc<Config>, resolver: &mut IconResolver) -> Result<Vars> {
    let snapshot = niri_snapshot(cfg, resolver)?;
    let mut vars = Vars::new();
    vars.insert(
        "niri_groups".to_string(),
        serde_json::to_string(&snapshot.groups)?,
    );
    Ok(vars)
}

fn run_audio_command(cfg: &Arc<Config>, command: AudioCommand) -> Result<()> {
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

    thread::sleep(Duration::from_millis(40));
    eww_update(cfg, &audio_vars(cfg)?)
}

fn run_brightness_command(cfg: &Arc<Config>, command: BrightnessCommand) -> Result<()> {
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

    thread::sleep(Duration::from_millis(40));
    eww_update(cfg, &brightness_vars(cfg)?)
}

fn run_media_command(cfg: &Arc<Config>, action: MediaAction) -> Result<()> {
    let action = match action {
        MediaAction::PlayPause => "play-pause",
        MediaAction::Stop => "stop",
        MediaAction::Previous => "previous",
        MediaAction::Next => "next",
    };
    let _ = status(cfg, &cfg.commands.playerctl, [action]);
    thread::sleep(Duration::from_millis(40));
    eww_update(cfg, &media_vars(cfg)?)
}

fn run_notification_command(cfg: &Arc<Config>, command: NotificationCommand) -> Result<()> {
    match command {
        NotificationCommand::Action => {
            notification_action(cfg)?;
            eww_update(cfg, &notification_vars(cfg, true)?)
        }
        NotificationCommand::MarkRead { id } => {
            if let Some(id) = id.or_else(|| env::var("id").ok()) {
                notification_mark_read(cfg, &id)?;
                eww_update(cfg, &notification_vars(cfg, false)?)
            } else {
                Ok(())
            }
        }
        NotificationCommand::MarkUnread { id } => {
            if let Some(id) = id.or_else(|| env::var("id").ok()) {
                notification_mark_unread(cfg, &id)?;
                eww_update(cfg, &notification_vars(cfg, false)?)
            } else {
                Ok(())
            }
        }
    }
}

fn reload_eww(cfg: &Arc<Config>) -> Result<()> {
    if eww_ping(cfg) {
        let _ = status(
            cfg,
            &cfg.commands.eww,
            ["--config", config_dir_arg(cfg), "reload"],
        );
        let _ = status(
            cfg,
            &cfg.commands.systemctl,
            ["--user", "try-restart", "framework-eww-bars.service"],
        );
    } else {
        let _ = status(
            cfg,
            &cfg.commands.systemctl,
            [
                "--user",
                "try-restart",
                "framework-eww.service",
                "framework-eww-bars.service",
            ],
        );
    }
    Ok(())
}

fn wait_for_eww(cfg: &Config) -> Result<()> {
    for _ in 0..100 {
        if eww_ping(cfg) {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(100));
    }
    Err(anyhow!("eww daemon did not become reachable"))
}

fn eww_ping(cfg: &Config) -> bool {
    command(cfg, &cfg.commands.eww)
        .args(["--config", config_dir_arg(cfg), "ping"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

fn eww_update(cfg: &Config, vars: &Vars) -> Result<()> {
    if vars.is_empty() {
        return Ok(());
    }

    let mappings = vars
        .iter()
        .map(|(name, value)| format!("{name}={}", sanitize_update_value(value)))
        .collect::<Vec<_>>();

    let mut cmd = command(cfg, &cfg.commands.eww);
    cmd.args(["--config", config_dir_arg(cfg), "update"]);
    cmd.args(mappings);

    let output = cmd.output().context("failed to run eww update")?;
    if output.status.success() {
        Ok(())
    } else {
        Err(anyhow!(
            "eww update failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ))
    }
}

fn sanitize_update_value(value: &str) -> String {
    value.replace(['\n', '\r'], " ")
}

fn open_bars_if_needed(cfg: &Config, outputs: &[String], last_outputs: &mut Vec<String>) -> bool {
    let mut outputs = outputs.to_vec();
    outputs.sort();
    outputs.dedup();
    if outputs.is_empty() {
        outputs.push("0".to_string());
    }

    if outputs == *last_outputs {
        return false;
    }
    *last_outputs = outputs.clone();

    let _ = status(
        cfg,
        &cfg.commands.eww,
        ["--config", config_dir_arg(cfg), "close-all"],
    );
    for output in outputs {
        let id = sanitize_id(&output);
        let window_id = format!("bar_{id}");
        let monitor_arg = format!("monitor={output}");
        let _ = status(
            cfg,
            &cfg.commands.eww,
            [
                "--config",
                config_dir_arg(cfg),
                "open",
                "--id",
                window_id.as_str(),
                "--arg",
                monitor_arg.as_str(),
                "bar",
            ],
        );
    }

    true
}

fn niri_snapshot(cfg: &Arc<Config>, resolver: &mut IconResolver) -> Result<NiriSnapshot> {
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

fn niri_json(cfg: &Config, message: &str, fallback: Value) -> Result<Value> {
    match output(cfg, &cfg.commands.niri, ["msg", "-j", message])? {
        Some(text) => serde_json::from_str(&text)
            .with_context(|| format!("failed to parse niri {message} JSON")),
        None => Ok(fallback),
    }
}

fn build_workspace(
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

fn build_window(window: &Value, resolver: &mut IconResolver) -> Option<NiriWindow> {
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

fn workspace_label(workspace: &Value) -> String {
    value_string(workspace, &["name"])
        .or_else(|| value_u64(workspace, &["idx"]).map(|value| value.to_string()))
        .or_else(|| value_u64(workspace, &["index"]).map(|value| value.to_string()))
        .or_else(|| value_u64(workspace, &["id"]).map(|value| value.to_string()))
        .unwrap_or_else(|| "?".to_string())
}

fn workspace_output(workspace: &Value) -> Option<String> {
    value_string(workspace, &["output", "output_name", "monitor"])
}

fn window_workspace_id(window: &Value) -> Option<u64> {
    value_u64(window, &["workspace_id", "workspace"])
}

fn window_order(window: Option<&Value>) -> Option<(i64, i64)> {
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

fn output_names(outputs: &Value) -> Vec<String> {
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

fn niri_event_affects_bar(event: &str) -> bool {
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

fn audio_vars(cfg: &Config) -> Result<Vars> {
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
struct AudioState {
    value: u8,
    muted: bool,
    device: String,
}

fn audio_device_state(cfg: &Config, device: AudioDevice) -> Result<AudioState> {
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

fn audio_target(device: AudioDevice) -> &'static str {
    match device {
        AudioDevice::Speaker => "@DEFAULT_AUDIO_SINK@",
        AudioDevice::Mic => "@DEFAULT_AUDIO_SOURCE@",
    }
}

fn parse_volume(text: &str) -> (u8, bool) {
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

fn parse_device_description(text: &str) -> Option<String> {
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

fn split_wpctl_property(line: &str, key: &str) -> Option<String> {
    let (line_key, value) = line.split_once(" = ")?;
    if !line_key.trim().ends_with(key) {
        return None;
    }
    Some(value.trim().trim_matches('"').to_string())
}

fn audio_event_affects_bar(event: &str) -> bool {
    event.contains(" on card")
        || event.contains(" on server")
        || event.contains(" on sink")
        || event.contains(" on source")
}

fn battery_vars(cfg: &Config) -> Result<Vars> {
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

fn battery_unknown_vars(cfg: &Config, foreground: &str) -> Vars {
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

fn display_device(cfg: &Config) -> Result<Option<String>> {
    let devices = output(cfg, &cfg.commands.upower, ["--enumerate"])?.unwrap_or_default();
    Ok(devices
        .lines()
        .find(|line| line.ends_with("DisplayDevice"))
        .map(str::to_string))
}

fn battery_device(cfg: &Config) -> Result<Option<String>> {
    let devices = output(cfg, &cfg.commands.upower, ["--enumerate"])?.unwrap_or_default();
    Ok(devices
        .lines()
        .find(|line| line.contains("/battery_"))
        .map(str::to_string))
}

fn upower_field(cfg: &Config, device: &str, field: &str) -> Result<Option<String>> {
    let info = output(cfg, &cfg.commands.upower, ["--show-info", device])?.unwrap_or_default();
    Ok(parse_colon_field(&info, field))
}

fn daemon_on_battery(cfg: &Config) -> Result<Option<String>> {
    let dump = output(cfg, &cfg.commands.upower, ["--dump"])?.unwrap_or_default();
    Ok(parse_colon_field(&dump, "on-battery"))
}

fn tlp_mode(cfg: &Config) -> Result<Option<String>> {
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

fn parse_colon_field(text: &str, field: &str) -> Option<String> {
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

fn battery_event_affects_bar(event: &str) -> bool {
    event.contains("device changed:")
        || event.contains("device added:")
        || event.contains("device removed:")
        || event.contains("daemon changed:")
}

fn brightness_vars(cfg: &Config) -> Result<Vars> {
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

fn parse_brightness_machine(text: &str) -> Option<u8> {
    text.split(',')
        .nth(3)?
        .trim()
        .trim_end_matches('%')
        .parse::<f64>()
        .ok()
        .map(|value| value.round().clamp(0.0, 100.0) as u8)
}

fn format_audio_set_value(value: f32) -> String {
    format!("{:.3}", value.clamp(0.0, 100.0) / 100.0)
}

fn format_brightness_set_value(value: f32) -> String {
    format!("{}%", value.round().clamp(1.0, 100.0) as u8)
}

fn perf_vars(cfg: &Config, sampler: &mut PerfSampler) -> Result<Vars> {
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

fn network_interface(cfg: &Config) -> String {
    if let Some(preferred) = &cfg.preferred_interface {
        if Path::new("/sys/class/net").join(preferred).is_dir() {
            return preferred.clone();
        }
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

fn network_rates(iface: &str, sampler: &mut PerfSampler) -> (String, String) {
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

fn network_vars(cfg: &Config) -> Result<Vars> {
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

fn parse_nmcli_field(text: &str, field: &str) -> Option<String> {
    text.lines().find_map(|line| {
        let (key, value) = line.split_once(':')?;
        (key == field).then(|| unescape_nmcli(value))
    })
}

fn parse_active_wifi_signal(text: &str) -> Option<u8> {
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

fn unescape_nmcli(value: &str) -> String {
    value.replace("\\:", ":").replace("\\\\", "\\")
}

fn ram_percent() -> Option<String> {
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
    if total == 0 {
        None
    } else {
        Some(format!("{}%", ((total - available) * 100) / total))
    }
}

fn cpu_percent(sampler: &mut PerfSampler) -> Option<String> {
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
    if total_delta == 0 {
        None
    } else {
        Some(format!(
            "{}%",
            (100 * (total_delta - idle_delta)) / total_delta
        ))
    }
}

fn gpu_percent() -> Option<String> {
    [
        "/sys/class/drm/card1/device/gpu_busy_percent",
        "/sys/class/drm/card0/device/gpu_busy_percent",
    ]
    .iter()
    .find_map(|path| read_u64(path).map(|value| format!("{value}%")))
}

fn read_u64(path: impl AsRef<Path>) -> Option<u64> {
    fs::read_to_string(path).ok()?.trim().parse().ok()
}

fn format_rate(value: u64) -> String {
    if value >= 1024 {
        format!("{:.1}M", value as f64 / 1024.0)
    } else {
        format!("{value}K")
    }
}

fn media_vars(cfg: &Config) -> Result<Vars> {
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

fn datetime_vars() -> Vars {
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

fn theme_vars(cfg: &Config) -> Vars {
    let mut vars = Vars::new();
    vars.insert(
        "cc_icon".to_string(),
        theme_color(cfg, "foreground", "#e5e5e5"),
    );
    vars.insert("cc_accent".to_string(), theme_color(cfg, "primary", "#60a5fa"));
    vars.insert(
        "cc_on_accent".to_string(),
        theme_color(cfg, "onPrimary", "#0b0f17"),
    );
    vars
}

fn notification_vars(cfg: &Config, prune: bool) -> Result<Vars> {
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

fn mako_notifications(cfg: &Config, command_name: &str) -> Result<Vec<MakoNotification>> {
    let text = output(cfg, &cfg.commands.makoctl, [command_name, "-j"])?.unwrap_or_default();
    if text.trim().is_empty() {
        Ok(Vec::new())
    } else {
        serde_json::from_str(&text)
            .with_context(|| format!("failed to parse makoctl {command_name} JSON"))
    }
}

fn notification_rows(
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

fn notification_row(
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

fn notification_preview(body: &str) -> String {
    if body.is_empty() {
        return "No details".to_string();
    }

    cap_text(body, NOTIFICATION_PREVIEW_CHARS)
}

fn cap_text(text: &str, max_chars: usize) -> String {
    let mut iter = text.chars();
    let preview = iter.by_ref().take(max_chars).collect::<String>();
    if iter.next().is_some() {
        format!("{preview}...")
    } else {
        preview
    }
}

struct NotificationState {
    unread_file: PathBuf,
    lock_file: PathBuf,
}

struct NotificationLock {
    file: File,
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

fn notification_state() -> Result<NotificationState> {
    let dir = runtime_dir().join("eww-notifications");
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

fn notification_mark_read(cfg: &Config, id: &str) -> Result<()> {
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

fn notification_mark_unread(cfg: &Config, id: &str) -> Result<()> {
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

fn notification_action(cfg: &Config) -> Result<()> {
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

fn mako_history_ids(cfg: &Config) -> Result<Vec<String>> {
    let history = output(cfg, &cfg.commands.makoctl, ["history"])?.unwrap_or_default();
    Ok(parse_mako_history_ids(&history))
}

fn parse_mako_history_ids(text: &str) -> Vec<String> {
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
        let cache_dir = runtime_dir().join("eww-icon-cache");
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

fn data_dirs(home: &Path) -> Vec<PathBuf> {
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

fn icon_themes(home: &Path) -> Vec<&'static str> {
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

fn read_desktop_key(path: &Path, wanted: &str) -> Option<String> {
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

fn find_icon_name(icon: &str, dirs: &[PathBuf], themes: &[&str]) -> Option<PathBuf> {
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

fn best_icon_match(icon: &str, root: &Path, max_depth: Option<usize>) -> Option<PathBuf> {
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

fn icon_file_matches(icon: &str, path: &Path) -> bool {
    let Some(file_name) = path.file_name().and_then(OsStr::to_str) else {
        return false;
    };
    file_name == icon
        || file_name == format!("{icon}.png")
        || file_name == format!("{icon}.svg")
        || file_name == format!("{icon}.xpm")
}

fn icon_rank(path: &Path) -> u8 {
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

fn cache_key(value: &str) -> String {
    let digest = Sha256::digest(value.as_bytes());
    digest.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn theme_color(cfg: &Config, name: &str, fallback: &str) -> String {
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

fn command(cfg: &Config, program: &Path) -> ProcessCommand {
    let mut cmd = ProcessCommand::new(program);
    cmd.env("HOME", &cfg.home);
    cmd.env("XDG_CONFIG_HOME", cfg.home.join(".config"));
    cmd
}

fn output<I, S>(cfg: &Config, program: &Path, args: I) -> Result<Option<String>>
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

fn status<I, S>(cfg: &Config, program: &Path, args: I) -> Result<()>
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

fn value_string(value: &Value, names: &[&str]) -> Option<String> {
    names
        .iter()
        .find_map(|name| value.get(*name).and_then(Value::as_str).map(str::to_string))
}

fn value_u64(value: &Value, names: &[&str]) -> Option<u64> {
    names.iter().find_map(|name| {
        let value = value.get(*name)?;
        value
            .as_u64()
            .or_else(|| value.as_str().and_then(|value| value.parse().ok()))
    })
}

fn value_bool(value: &Value, names: &[&str]) -> bool {
    names
        .iter()
        .any(|name| value.get(*name).and_then(Value::as_bool).unwrap_or(false))
}

fn runtime_dir() -> PathBuf {
    env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"))
}

fn config_dir_arg(cfg: &Config) -> &str {
    cfg.eww_config_dir.to_str().unwrap_or(".")
}

fn sanitize_id(value: &str) -> String {
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
    fn merges_desired_vars_with_resync_sentinel() {
        let mut desired = Vars::new();
        desired.insert("battery_value".to_string(), "42".to_string());

        let mut vars = Vars::new();
        vars.insert(FORCE_RESYNC_VAR.to_string(), "1".to_string());
        vars.insert("battery_color".to_string(), "#ffffff".to_string());

        assert!(merge_desired_vars(&mut desired, vars));
        assert_eq!(desired.get("battery_value").map(String::as_str), Some("42"));
        assert_eq!(
            desired.get("battery_color").map(String::as_str),
            Some("#ffffff")
        );
        assert!(!desired.contains_key(FORCE_RESYNC_VAR));
    }

    #[test]
    fn sanitizes_bar_ids() {
        assert_eq!(sanitize_id("eDP-1"), "eDP_1");
        assert_eq!(sanitize_id("HDMI A 1"), "HDMI_A_1");
    }
}
