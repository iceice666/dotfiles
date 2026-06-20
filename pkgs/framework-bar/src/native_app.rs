use std::{
    collections::HashMap,
    io::{BufRead, BufReader},
    path::{Path, PathBuf},
    process::{Command as ProcessCommand, Stdio},
    sync::Arc,
    thread,
    time::Duration,
};

use anyhow::Result;
use chrono::{Datelike, Local, NaiveDate};
use iced::widget::canvas::{self, LineCap, Path as CanvasPath, Stroke, path};
use iced::widget::{
    button, column, container, image, mouse_area, row, scrollable, slider, space, stack, svg, text,
    text_input,
};
use iced::{
    Alignment, Background, Border, Color, Element, Font, Length, Pixels, Point, Radians, Rectangle,
    Subscription, Task, Theme, alignment,
};
use iced_layershell::{
    reexport::{Anchor, IcedId, KeyboardInteractivity, Layer, NewLayerShellSettings, OutputOption},
    settings::{LayerShellSettings, StartMode},
    to_layer_message,
};
use system_tray::menu::{MenuItem, MenuType, ToggleState, TrayMenu};

use crate::ipc::{self, RefreshDomain};
use crate::state::{BarData, CcView, Palette, UiState, battery_ring_color};
use crate::systray::{self, TrayEvent, TrayIcon, TrayItem, TrayItems};
use crate::{
    AudioCommand, AudioDevice, BrightnessCommand, Config, IconResolver, MediaAction, PerfSampler,
    Vars, audio_vars, battery_vars, brightness_vars, command, datetime_vars, media_vars,
    network_vars, niri_event_affects_bar, niri_snapshot, notification_vars, perf_vars,
    run_audio_command, run_brightness_command, run_media_command, status, theme_vars,
    toggle_state_vars, wifi_connect, wifi_disconnect, wifi_rescan, wifi_vars,
};

const BAR_HEIGHT: f32 = 32.0;
const BAR_TEXT_LINE_HEIGHT: f32 = 1.0;
const BAR_RING_SIZE: f32 = 30.0;
const BAR_WINDOW_ICON_SIZE: f32 = 24.0;
const BAR_TRAY_ICON_SIZE: f32 = 20.0;

#[derive(Debug, Clone, PartialEq, Eq)]
enum WindowKind {
    Bar(String),
    ControlCenter,
    Calendar,
}

pub struct App {
    cfg: Arc<Config>,
    data: BarData,
    palette: Palette,
    ui: UiState,
    windows: HashMap<IcedId, WindowKind>,
    bars: HashMap<String, IcedId>,
    control_center: Option<IcedId>,
    calendar: Option<IcedId>,
    overlay_output: String,
    resolver: IconResolver,
    sampler: PerfSampler,
    tray: TrayItems,
    tray_menu: Option<String>,
}

#[to_layer_message(multi)]
#[derive(Debug, Clone)]
enum Message {
    Refresh(RefreshDomain),
    Vars(Vars),
    Niri {
        vars: Vars,
        outputs: Vec<String>,
    },
    Palette(Palette),
    Tray(TrayEvent),
    ToggleControlCenter(String),
    ToggleCalendar(String),
    CloseControlCenter,
    CloseCalendar,
    SetCcView(CcView),
    BatteryReveal(bool),
    SystrayReveal(bool),
    FocusWindow(u64),
    AudioSet(AudioDevice, f32),
    AudioToggle(AudioDevice),
    BrightnessSet(f32),
    Media(MediaAction),
    OpenPavucontrol,
    ToggleSetting(&'static str),
    WifiRescan,
    WifiConnect(String),
    WifiDisconnect,
    WifiPasswordChanged(String),
    WifiPasswordTarget(String),
    ToggleNotification(String),
    ClearNotifications,
    Session(&'static str),
    TrayActivate(String),
    TrayMenu(String),
    TrayMenuItem {
        address: String,
        menu_path: String,
        id: i32,
    },
    Noop,
}

pub fn run(cfg: Arc<Config>) -> Result<()> {
    iced_layershell::disable_clipboard();
    iced_layershell::daemon(
        move || boot(cfg.clone()),
        || "framework-bar".to_string(),
        update,
        view,
    )
    .subscription(subscription)
    .style(|state, _| iced::theme::Style {
        background_color: Color::TRANSPARENT,
        text_color: state.palette.foreground,
    })
    .settings(iced_layershell::Settings {
        id: Some("framework-bar".to_string()),
        layer_settings: LayerShellSettings {
            start_mode: StartMode::Background,
            ..LayerShellSettings::default()
        },
        default_font: Font::with_name("Sarasa Mono TC"),
        default_text_size: Pixels(13.0),
        antialiasing: true,
        ..iced_layershell::Settings::default()
    })
    .run()
    .map_err(Into::into)
}

fn boot(cfg: Arc<Config>) -> (App, Task<Message>) {
    let app = App {
        resolver: IconResolver::new(cfg.clone()),
        palette: Palette::from_config(&cfg),
        cfg,
        data: BarData::default(),
        ui: UiState::default(),
        windows: HashMap::new(),
        bars: HashMap::new(),
        control_center: None,
        calendar: None,
        overlay_output: "0".to_string(),
        sampler: PerfSampler::default(),
        tray: TrayItems::new(),
        tray_menu: None,
    };
    (app, Task::done(Message::Refresh(RefreshDomain::All)))
}

fn subscription(app: &App) -> Subscription<Message> {
    Subscription::batch([
        tick(Duration::from_secs(30), RefreshDomain::Niri),
        tick(Duration::from_secs(2), RefreshDomain::Audio),
        tick(Duration::from_secs(5), RefreshDomain::Battery),
        tick(Duration::from_secs(2), RefreshDomain::Brightness),
        tick(Duration::from_secs(1), RefreshDomain::Perf),
        tick(Duration::from_secs(2), RefreshDomain::Media),
        tick(Duration::from_secs(1), RefreshDomain::Datetime),
        tick(Duration::from_secs(10), RefreshDomain::Network),
        tick(Duration::from_secs(3), RefreshDomain::Theme),
        tick(Duration::from_secs(5), RefreshDomain::Notifications),
        tick(Duration::from_secs(6), RefreshDomain::Toggles),
        tick(Duration::from_secs(12), RefreshDomain::Wifi),
        niri_event_subscription(&app.cfg),
        ipc::subscription().map(Message::Refresh),
        systray::subscription().map(Message::Tray),
    ])
}

fn tick(duration: Duration, domain: RefreshDomain) -> Subscription<Message> {
    iced::time::every(duration)
        .with(domain)
        .map(|(domain, _)| Message::Refresh(domain))
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct NiriEventConfig {
    niri: PathBuf,
    home: PathBuf,
}

fn niri_event_subscription(cfg: &Arc<Config>) -> Subscription<Message> {
    Subscription::run_with(
        NiriEventConfig {
            niri: cfg.commands.niri.clone(),
            home: cfg.home.clone(),
        },
        niri_events,
    )
    .map(Message::Refresh)
}

fn niri_events(
    config: &NiriEventConfig,
) -> futures::channel::mpsc::UnboundedReceiver<RefreshDomain> {
    let config = config.clone();
    let (sender, receiver) = futures::channel::mpsc::unbounded();

    thread::spawn(move || {
        loop {
            let mut child = match ProcessCommand::new(&config.niri)
                .env("HOME", &config.home)
                .env("XDG_CONFIG_HOME", config.home.join(".config"))
                .args(["msg", "-j", "event-stream"])
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()
            {
                Ok(child) => child,
                Err(_) => {
                    thread::sleep(Duration::from_secs(1));
                    continue;
                }
            };

            if let Some(stdout) = child.stdout.take() {
                let reader = BufReader::new(stdout);
                for line in reader.lines() {
                    let Ok(line) = line else {
                        break;
                    };
                    if niri_event_affects_bar(&line)
                        && sender.unbounded_send(RefreshDomain::Niri).is_err()
                    {
                        let _ = child.kill();
                        return;
                    }
                }
            }

            let _ = child.kill();
            let _ = child.wait();
            thread::sleep(Duration::from_secs(1));
        }
    });

    receiver
}

fn update(app: &mut App, message: Message) -> Task<Message> {
    match message {
        Message::Refresh(domain) => refresh(app, domain),
        Message::Vars(vars) => {
            app.data.apply_vars(&vars);
            Task::none()
        }
        Message::Niri { vars, outputs } => {
            app.data.apply_vars(&vars);
            reconcile_outputs(app, outputs)
        }
        Message::Palette(palette) => {
            app.palette = palette;
            Task::none()
        }
        Message::Tray(event) => {
            systray::apply_event(&mut app.tray, &mut app.resolver, event);
            Task::none()
        }
        Message::ToggleControlCenter(output) => toggle_control_center(app, output),
        Message::ToggleCalendar(output) => toggle_calendar(app, output),
        Message::CloseControlCenter => remove_overlay(app.control_center.take(), &mut app.windows),
        Message::CloseCalendar => remove_overlay(app.calendar.take(), &mut app.windows),
        Message::SetCcView(view) => {
            app.ui.cc_view = view;
            Task::none()
        }
        Message::BatteryReveal(revealed) => {
            app.ui.battery_revealed = revealed;
            Task::none()
        }
        Message::SystrayReveal(revealed) => {
            app.ui.systray_revealed = revealed;
            Task::none()
        }
        Message::FocusWindow(id) => run_command_task({
            let cfg = app.cfg.clone();
            move || {
                status(
                    &cfg,
                    &cfg.commands.niri,
                    ["msg", "action", "focus-window", "--id", &id.to_string()],
                )
            }
        }),
        Message::AudioSet(device, value) => action_refresh(
            {
                let cfg = app.cfg.clone();
                move || run_audio_command(&cfg, AudioCommand::Set { device, value })
            },
            RefreshDomain::Audio,
        ),
        Message::AudioToggle(device) => action_refresh(
            {
                let cfg = app.cfg.clone();
                move || run_audio_command(&cfg, AudioCommand::Toggle { device })
            },
            RefreshDomain::Audio,
        ),
        Message::BrightnessSet(value) => action_refresh(
            {
                let cfg = app.cfg.clone();
                move || run_brightness_command(&cfg, BrightnessCommand::Set { value })
            },
            RefreshDomain::Brightness,
        ),
        Message::Media(action) => action_refresh(
            {
                let cfg = app.cfg.clone();
                move || run_media_command(&cfg, action)
            },
            RefreshDomain::Media,
        ),
        Message::OpenPavucontrol => run_command_task({
            let cfg = app.cfg.clone();
            move || {
                command(&cfg, &cfg.commands.pavucontrol)
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .spawn()?;
                Ok(())
            }
        }),
        Message::ToggleSetting(target) => action_refresh(
            {
                let cfg = app.cfg.clone();
                move || crate::cc_toggle(&cfg, target)
            },
            RefreshDomain::Toggles,
        ),
        Message::WifiRescan => action_refresh(
            {
                let cfg = app.cfg.clone();
                move || wifi_rescan(&cfg)
            },
            RefreshDomain::Wifi,
        ),
        Message::WifiConnect(ssid) => {
            let password = app.ui.wifi_password.clone();
            app.ui.wifi_password.clear();
            app.ui.wifi_pw_target.clear();
            action_refresh(
                {
                    let cfg = app.cfg.clone();
                    move || wifi_connect(&cfg, &ssid, &password)
                },
                RefreshDomain::Wifi,
            )
        }
        Message::WifiDisconnect => action_refresh(
            {
                let cfg = app.cfg.clone();
                move || wifi_disconnect(&cfg)
            },
            RefreshDomain::Wifi,
        ),
        Message::WifiPasswordChanged(value) => {
            app.ui.wifi_password = value;
            Task::none()
        }
        Message::WifiPasswordTarget(target) => {
            if app.ui.wifi_pw_target == target {
                app.ui.wifi_pw_target.clear();
            } else {
                app.ui.wifi_pw_target = target;
                app.ui.wifi_password.clear();
            }
            Task::none()
        }
        Message::ToggleNotification(key) => {
            if app.ui.notification_expanded_id == key {
                app.ui.notification_expanded_id = "__none".to_string();
            } else {
                app.ui.notification_expanded_id = key;
            }
            Task::none()
        }
        Message::ClearNotifications => action_refresh(
            {
                let cfg = app.cfg.clone();
                move || status(&cfg, &cfg.commands.makoctl, ["dismiss", "--all"])
            },
            RefreshDomain::Notifications,
        ),
        Message::Session(action) => session_task(app.cfg.clone(), action),
        Message::TrayActivate(address) => systray::activate_default(address).map(|_| Message::Noop),
        Message::TrayMenu(address) => {
            app.tray_menu = if app.tray_menu.as_deref() == Some(address.as_str()) {
                None
            } else {
                Some(address.clone())
            };
            if let Some(menu_path) = app
                .tray
                .get(&address)
                .and_then(|item| item.item.menu.clone())
            {
                systray::about_to_show(address, menu_path).map(|_| Message::Noop)
            } else {
                systray::activate_secondary(address).map(|_| Message::Noop)
            }
        }
        Message::TrayMenuItem {
            address,
            menu_path,
            id,
        } => systray::activate_menu(address, menu_path, id).map(|_| Message::Noop),
        Message::Noop => Task::none(),
        _ => Task::none(),
    }
}

fn view(app: &App, id: IcedId) -> Element<'_, Message> {
    match app.windows.get(&id) {
        Some(WindowKind::Bar(output)) => bar_view(app, output),
        Some(WindowKind::ControlCenter) => control_center_view(app),
        Some(WindowKind::Calendar) => calendar_view(app),
        None => space().into(),
    }
}

fn refresh(app: &mut App, domain: RefreshDomain) -> Task<Message> {
    match domain {
        RefreshDomain::Perf => {
            if let Ok(vars) = perf_vars(&app.cfg, &mut app.sampler) {
                app.data.apply_vars(&vars);
            }
            Task::none()
        }
        RefreshDomain::All => {
            if let Ok(vars) = perf_vars(&app.cfg, &mut app.sampler) {
                app.data.apply_vars(&vars);
            }
            Task::batch([
                niri_task(app.cfg.clone()),
                collect_task(app.cfg.clone(), RefreshDomain::Audio),
                collect_task(app.cfg.clone(), RefreshDomain::Battery),
                collect_task(app.cfg.clone(), RefreshDomain::Brightness),
                collect_task(app.cfg.clone(), RefreshDomain::Media),
                collect_task(app.cfg.clone(), RefreshDomain::Datetime),
                collect_task(app.cfg.clone(), RefreshDomain::Network),
                collect_task(app.cfg.clone(), RefreshDomain::Notifications),
                collect_task(app.cfg.clone(), RefreshDomain::Toggles),
                collect_task(app.cfg.clone(), RefreshDomain::Wifi),
                theme_task(app.cfg.clone()),
            ])
        }
        RefreshDomain::Niri => niri_task(app.cfg.clone()),
        RefreshDomain::Theme => theme_task(app.cfg.clone()),
        _ => collect_task(app.cfg.clone(), domain),
    }
}

fn collect_task(cfg: Arc<Config>, domain: RefreshDomain) -> Task<Message> {
    Task::perform(
        async move {
            let mut vars = Vars::new();
            match domain {
                RefreshDomain::Audio => vars.extend(audio_vars(&cfg).unwrap_or_default()),
                RefreshDomain::Battery => vars.extend(battery_vars(&cfg).unwrap_or_default()),
                RefreshDomain::Brightness => vars.extend(brightness_vars(&cfg).unwrap_or_default()),
                RefreshDomain::Media => vars.extend(media_vars(&cfg).unwrap_or_default()),
                RefreshDomain::Datetime => vars.extend(datetime_vars()),
                RefreshDomain::Network => vars.extend(network_vars(&cfg).unwrap_or_default()),
                RefreshDomain::Notifications => {
                    vars.extend(notification_vars(&cfg, true).unwrap_or_default())
                }
                RefreshDomain::Toggles => vars.extend(toggle_state_vars(&cfg)),
                RefreshDomain::Wifi => vars.extend(wifi_vars(&cfg)),
                _ => {}
            }
            vars
        },
        Message::Vars,
    )
}

fn niri_task(cfg: Arc<Config>) -> Task<Message> {
    Task::perform(
        async move {
            let mut resolver = IconResolver::new(cfg.clone());
            match niri_snapshot(&cfg, &mut resolver) {
                Ok(snapshot) => {
                    let mut vars = Vars::new();
                    vars.insert(
                        "niri_groups".to_string(),
                        serde_json::to_string(&snapshot.groups)
                            .unwrap_or_else(|_| "[]".to_string()),
                    );
                    let mut outputs = snapshot.outputs;
                    if outputs.is_empty() {
                        outputs.push("0".to_string());
                    }
                    Message::Niri { vars, outputs }
                }
                Err(_) => {
                    let mut vars = Vars::new();
                    vars.insert("niri_groups".to_string(), "[]".to_string());
                    Message::Niri {
                        vars,
                        outputs: vec!["0".to_string()],
                    }
                }
            }
        },
        std::convert::identity,
    )
}

fn theme_task(cfg: Arc<Config>) -> Task<Message> {
    Task::batch([
        Task::perform(
            {
                let cfg = cfg.clone();
                async move { theme_vars(&cfg) }
            },
            Message::Vars,
        ),
        Task::perform(async move { Palette::from_config(&cfg) }, Message::Palette),
    ])
}

fn reconcile_outputs(app: &mut App, mut outputs: Vec<String>) -> Task<Message> {
    outputs.sort();
    outputs.dedup();
    if outputs.is_empty() {
        outputs.push("0".to_string());
    }

    let wanted = outputs
        .iter()
        .cloned()
        .collect::<std::collections::HashSet<_>>();
    let stale = app
        .bars
        .keys()
        .filter(|output| !wanted.contains(*output))
        .cloned()
        .collect::<Vec<_>>();
    let mut tasks = Vec::new();

    for output in stale {
        if let Some(id) = app.bars.remove(&output) {
            app.windows.remove(&id);
            tasks.push(Task::done(Message::RemoveWindow(id)));
        }
    }

    for output in outputs {
        if app.bars.contains_key(&output) {
            continue;
        }
        let (id, task) = Message::layershell_open(bar_settings(&output));
        app.windows.insert(id, WindowKind::Bar(output.clone()));
        app.bars.insert(output, id);
        tasks.push(task);
    }

    Task::batch(tasks)
}

fn toggle_control_center(app: &mut App, output: String) -> Task<Message> {
    if let Some(id) = app.control_center.take() {
        app.windows.remove(&id);
        return Task::done(Message::RemoveWindow(id));
    }
    app.ui.cc_view = CcView::Home;
    app.overlay_output = output.clone();
    let (id, task) = Message::layershell_open(overlay_settings(
        &output,
        "framework-eww-control-center",
        KeyboardInteractivity::OnDemand,
    ));
    app.windows.insert(id, WindowKind::ControlCenter);
    app.control_center = Some(id);
    task
}

fn toggle_calendar(app: &mut App, output: String) -> Task<Message> {
    if let Some(id) = app.calendar.take() {
        app.windows.remove(&id);
        return Task::done(Message::RemoveWindow(id));
    }
    app.overlay_output = output.clone();
    let (id, task) = Message::layershell_open(overlay_settings(
        &output,
        "framework-eww-calendar",
        KeyboardInteractivity::None,
    ));
    app.windows.insert(id, WindowKind::Calendar);
    app.calendar = Some(id);
    task
}

fn remove_overlay(id: Option<IcedId>, windows: &mut HashMap<IcedId, WindowKind>) -> Task<Message> {
    if let Some(id) = id {
        windows.remove(&id);
        Task::done(Message::RemoveWindow(id))
    } else {
        Task::none()
    }
}

fn bar_view<'a>(app: &'a App, output: &'a str) -> Element<'a, Message> {
    let p = app.palette;
    let left = container(app_strip(app, output))
        .width(Length::FillPortion(2))
        .clip(true)
        .align_x(alignment::Horizontal::Left);
    let media_center: Element<'a, Message> = if app.data.media_text.is_empty() {
        space().into()
    } else {
        island(
            text(limit(&app.data.media_text, 52)).line_height(BAR_TEXT_LINE_HEIGHT),
            p,
        )
        .into()
    };
    let center = container(media_center)
        .clip(true)
        .align_x(alignment::Horizontal::Center);
    let right = container(
        row![
            perf_module(app),
            battery_module(app),
            systray_module(app),
            datetime_module(app, output),
            control_center_button(app, output),
        ]
        .spacing(2)
        .align_y(Alignment::Center),
    )
    .width(Length::FillPortion(2))
    .clip(true)
    .align_x(alignment::Horizontal::Right);

    container(
        row![left, center, right]
            .spacing(2)
            .padding([0, 2])
            .height(Length::Fixed(BAR_HEIGHT))
            .align_y(Alignment::Center)
            .clip(true),
    )
    .width(Length::Fill)
    .height(Length::Fixed(BAR_HEIGHT))
    .into()
}

fn app_strip<'a>(app: &'a App, output: &'a str) -> Element<'a, Message> {
    let mut strip = row![].spacing(4).align_y(Alignment::Center);
    for group in app
        .data
        .niri_groups
        .iter()
        .filter(|group| group.monitor == output)
    {
        for workspace in &group.workspaces {
            strip = strip.push(
                island(
                    text(workspace.label.clone())
                        .size(14)
                        .line_height(BAR_TEXT_LINE_HEIGHT),
                    app.palette,
                )
                .padding([4, 8]),
            );
            for window in &workspace.windows {
                let mut content = row![icon_path(
                    Path::new(&window.icon_path),
                    None,
                    BAR_WINDOW_ICON_SIZE
                )]
                .spacing(6)
                .align_y(Alignment::Center);
                if window.focused {
                    content = content.push(
                        text(limit(&window.title, 28))
                            .line_height(BAR_TEXT_LINE_HEIGHT)
                            .color(app.palette.primary),
                    );
                }
                let p = app.palette;
                strip = strip.push(
                    button(content)
                        .padding([4, 8])
                        .height(Length::Fixed(BAR_HEIGHT))
                        .style(move |_, status| island_button_style(p, status, window.focused))
                        .on_press(Message::FocusWindow(window.id)),
                );
            }
        }
    }
    strip.into()
}

fn perf_module(app: &App) -> Element<'_, Message> {
    island(
        row![
            perf_col("CPU", &app.data.perf_cpu, app.palette),
            perf_col("RAM", &app.data.perf_ram, app.palette),
            perf_col("GPU", &app.data.perf_gpu, app.palette),
            column![
                perf_net("UP", format!("{}/s", app.data.perf_up), app.palette),
                perf_net("DN", format!("{}/s", app.data.perf_down), app.palette),
            ]
        ]
        .spacing(3)
        .align_y(Alignment::Center),
        app.palette,
    )
    .padding([3, 4])
    .into()
}

fn perf_col<'a>(label: &'a str, value: &'a str, p: Palette) -> Element<'a, Message> {
    column![
        text(label)
            .size(10)
            .line_height(BAR_TEXT_LINE_HEIGHT)
            .color(p.foreground_dim),
        text(value)
            .line_height(BAR_TEXT_LINE_HEIGHT)
            .color(p.primary),
    ]
    .align_x(Alignment::End)
    .width(Length::Fixed(28.0))
    .into()
}

fn perf_net<'a>(label: &'a str, value: String, p: Palette) -> Element<'a, Message> {
    row![
        text(label)
            .size(10)
            .line_height(BAR_TEXT_LINE_HEIGHT)
            .color(p.foreground_dim)
            .width(Length::Fixed(14.0)),
        text(value)
            .line_height(BAR_TEXT_LINE_HEIGHT)
            .color(p.primary)
            .width(Length::Fixed(44.0)),
    ]
    .spacing(3)
    .align_y(Alignment::Center)
    .height(Length::Fixed(14.0))
    .into()
}

fn battery_module(app: &App) -> Element<'_, Message> {
    let ring_color = battery_ring_color(&app.data.battery_class, app.palette);
    let ring = canvas::Canvas::new(BatteryRing {
        value: app.data.battery_value.clamp(0.0, 100.0),
        color: ring_color,
        track: app.palette.surface_active,
    })
    .width(Length::Fixed(BAR_RING_SIZE))
    .height(Length::Fixed(BAR_RING_SIZE));
    let mut content = row![stack([
        ring.into(),
        container(icon_path(
            &app.data.battery_icon,
            Some(app.data.battery_color),
            18.0
        ))
        .width(Length::Fixed(BAR_RING_SIZE))
        .height(Length::Fixed(BAR_RING_SIZE))
        .align_x(alignment::Horizontal::Center)
        .align_y(alignment::Vertical::Center)
        .into(),
    ])]
    .align_y(Alignment::Center);
    if app.ui.battery_revealed {
        content = content.push(label_pill(app.data.battery_tooltip.clone(), app.palette));
    }
    mouse_area(island(content, app.palette).padding([1, 4]))
        .on_enter(Message::BatteryReveal(true))
        .on_exit(Message::BatteryReveal(false))
        .into()
}

fn systray_module(app: &App) -> Element<'_, Message> {
    let mut icons = row![icon_path(
        &app.cfg.icons.tray,
        Some(app.data.battery_color),
        BAR_TRAY_ICON_SIZE
    )]
    .spacing(2)
    .align_y(Alignment::Center);
    if app.ui.systray_revealed {
        for item in app.tray.values() {
            let address = item.address.clone();
            icons = icons.push(
                mouse_area(tray_icon_view(
                    item,
                    &app.cfg.icons.tray,
                    app.data.battery_color,
                ))
                .on_press(Message::TrayActivate(address.clone()))
                .on_right_press(Message::TrayMenu(address)),
            );
        }
    }
    let mut content = column![
        mouse_area(island(icons, app.palette).padding([1, 4]))
            .on_enter(Message::SystrayReveal(true))
            .on_exit(Message::SystrayReveal(false))
    ];
    if let Some(address) = &app.tray_menu
        && let Some(item) = app.tray.get(address)
        && let (Some(menu), Some(menu_path)) = (&item.menu, &item.item.menu)
    {
        content = content.push(tray_menu_view(address, menu_path, menu, app.palette));
    }
    content.into()
}

fn datetime_module<'a>(app: &'a App, output: &'a str) -> Element<'a, Message> {
    button(
        island(
            column![
                text(app.data.datetime_date.clone())
                    .size(12)
                    .line_height(BAR_TEXT_LINE_HEIGHT)
                    .color(app.palette.foreground),
                text(app.data.datetime_time.clone())
                    .size(16)
                    .line_height(BAR_TEXT_LINE_HEIGHT)
                    .color(app.palette.primary),
            ]
            .align_x(Alignment::Center),
            app.palette,
        )
        .padding([1, 6]),
    )
    .padding(0)
    .height(Length::Fixed(BAR_HEIGHT))
    .style(transparent_button)
    .on_press(Message::ToggleCalendar(output.to_string()))
    .into()
}

fn control_center_button<'a>(app: &'a App, output: &'a str) -> Element<'a, Message> {
    let color = if app.data.notifications_count > 0 {
        app.data.notifications_color
    } else {
        app.data.battery_color
    };
    let mut badge = stack(vec![
        container(icon_path(&app.cfg.icons.control_center, Some(color), 23.0))
            .width(Length::Fixed(32.0))
            .height(Length::Fixed(26.0))
            .align_x(alignment::Horizontal::Center)
            .align_y(alignment::Vertical::Center)
            .into(),
    ]);
    if app.data.notifications_count > 0 {
        badge = stack(vec![
            badge.into(),
            container(
                text(app.data.notifications_label.clone())
                    .size(10)
                    .line_height(BAR_TEXT_LINE_HEIGHT)
                    .color(app.palette.on_critical),
            )
            .padding([0, 3])
            .style(move |_| container_style(app.palette.critical, app.palette.critical, 999.0))
            .align_x(alignment::Horizontal::Right)
            .into(),
        ]);
    }
    button(island(badge, app.palette).padding([2, 5]))
        .padding(0)
        .height(Length::Fixed(BAR_HEIGHT))
        .style(transparent_button)
        .on_press(Message::ToggleControlCenter(output.to_string()))
        .into()
}

fn control_center_view(app: &App) -> Element<'_, Message> {
    let content = match app.ui.cc_view {
        CcView::Home => cc_home(app),
        CcView::Wifi => cc_wifi_view(app),
        CcView::Sound => cc_sound_view(app),
        CcView::Notifications => cc_notifications_view(app),
        CcView::Session => cc_session_view(app),
    };
    overlay_panel(content, app.palette, Message::CloseControlCenter, false)
}

fn cc_home(app: &App) -> Element<'_, Message> {
    let mut content = column![
        row![
            wifi_tile(app),
            cc_toggle(
                app,
                &app.cfg.icons.bluetooth,
                "Bluetooth",
                app.data.cc_bt,
                Message::ToggleSetting("bt")
            ),
        ]
        .spacing(8),
        row![
            cc_toggle(
                app,
                &app.cfg.icons.notification,
                "Silence",
                app.data.cc_dnd,
                Message::ToggleSetting("dnd")
            ),
            cc_toggle(
                app,
                &app.cfg.icons.dark_mode,
                "Dark",
                app.data.cc_dark,
                Message::ToggleSetting("dark")
            ),
        ]
        .spacing(8),
        cc_section(
            column![
                audio_slider(app, AudioDevice::Speaker),
                brightness_slider(app)
            ]
            .spacing(8),
            app.palette
        ),
    ]
    .spacing(10);
    if !app.data.media_text.is_empty() {
        content = content.push(media_panel(app));
    }
    content = content.push(cc_section(
        column![
            cc_row(
                app,
                &app.cfg.icons.speaker_high,
                "Sound",
                &app.data.audio_speaker.device,
                CcView::Sound
            ),
            cc_row(
                app,
                &app.cfg.icons.notification,
                "Notifications",
                "",
                CcView::Notifications
            ),
            cc_row(app, &app.cfg.icons.lock, "Power", "", CcView::Session),
        ]
        .spacing(2),
        app.palette,
    ));
    content.into()
}

fn wifi_tile(app: &App) -> Element<'_, Message> {
    let p = app.palette;
    button(
        row![
            icon_path(
                &app.cfg.icons.network,
                Some(if app.data.cc_wifi {
                    p.primary
                } else {
                    p.foreground
                }),
                20.0
            ),
            column![
                text("Wi-Fi").color(if app.data.cc_wifi {
                    p.primary
                } else {
                    p.foreground
                }),
                text(app.data.network_label.clone())
                    .size(10)
                    .color(if app.data.cc_wifi {
                        p.primary
                    } else {
                        p.foreground_dim
                    }),
            ]
            .width(Length::Fill),
            text("›").size(18).color(p.foreground_dim),
        ]
        .spacing(8)
        .align_y(Alignment::Center),
    )
    .width(Length::Fill)
    .padding([9, 10])
    .style(move |_, status| toggle_button_style(p, status, app.data.cc_wifi))
    .on_press(Message::SetCcView(CcView::Wifi))
    .into()
}

fn cc_toggle<'a>(
    app: &'a App,
    icon: &'a Path,
    label: &'a str,
    on: bool,
    press: Message,
) -> Element<'a, Message> {
    let p = app.palette;
    button(
        row![
            icon_path(icon, Some(if on { p.primary } else { p.foreground }), 20.0),
            column![
                text(label).color(if on { p.primary } else { p.foreground }),
                text(if on { "On" } else { "Off" }).size(10).color(if on {
                    p.primary
                } else {
                    p.foreground_dim
                }),
            ]
            .width(Length::Fill),
        ]
        .spacing(8)
        .align_y(Alignment::Center),
    )
    .width(Length::Fill)
    .padding([9, 10])
    .style(move |_, status| toggle_button_style(p, status, on))
    .on_press(press)
    .into()
}

fn media_panel(app: &App) -> Element<'_, Message> {
    cc_section(
        column![
            row![
                icon_path(&app.cfg.icons.media, Some(app.palette.foreground), 22.0),
                text("Now Playing")
            ]
            .spacing(8),
            text(limit(&app.data.media_text, 44)).color(app.palette.foreground_dim),
            row![
                action_button("Prev", Message::Media(MediaAction::Previous), app.palette),
                action_button("Play", Message::Media(MediaAction::PlayPause), app.palette),
                action_button("Next", Message::Media(MediaAction::Next), app.palette),
            ]
            .spacing(8),
        ]
        .spacing(8),
        app.palette,
    )
}

fn cc_row<'a>(
    app: &'a App,
    icon: &'a Path,
    title: &'a str,
    sub: &'a str,
    view: CcView,
) -> Element<'a, Message> {
    button(
        row![
            icon_path(icon, Some(app.palette.foreground), 20.0),
            column![
                text(title),
                text(sub).size(11).color(app.palette.foreground_dim)
            ]
            .width(Length::Fill),
            text("›").size(18).color(app.palette.foreground_dim),
        ]
        .spacing(10)
        .align_y(Alignment::Center),
    )
    .padding(8)
    .style(move |_, status| flat_button_style(app.palette, status))
    .on_press(Message::SetCcView(view))
    .into()
}

fn cc_wifi_view(app: &App) -> Element<'_, Message> {
    let mut list = column![].spacing(4);
    for network in &app.data.wifi_networks {
        let ssid = network.ssid.clone();
        let action = if network.known || network.security.is_empty() {
            Message::WifiConnect(ssid.clone())
        } else {
            Message::WifiPasswordTarget(ssid.clone())
        };
        let mut entry = column![
            button(
                row![
                    icon_path(
                        &app.cfg.icons.network,
                        Some(if network.active {
                            app.palette.primary
                        } else {
                            app.palette.foreground
                        }),
                        18.0
                    ),
                    text(limit(&network.ssid, 25))
                        .color(if network.active {
                            app.palette.primary
                        } else {
                            app.palette.foreground
                        })
                        .width(Length::Fill),
                    text(if network.security.is_empty() {
                        ""
                    } else {
                        ""
                    })
                    .color(app.palette.foreground_dim),
                    text(format!("{}%", network.signal))
                        .size(11)
                        .color(app.palette.foreground_dim),
                ]
                .spacing(8)
                .align_y(Alignment::Center),
            )
            .width(Length::Fill)
            .padding([6, 8])
            .style(move |_, status| active_row_style(app.palette, status, network.active))
            .on_press(action)
        ];
        if app.ui.wifi_pw_target == network.ssid {
            entry = entry.push(
                row![
                    text_input("Password", &app.ui.wifi_password)
                        .secure(true)
                        .on_input(Message::WifiPasswordChanged)
                        .on_submit(Message::WifiConnect(ssid.clone()))
                        .width(Length::Fill),
                    action_button("Join", Message::WifiConnect(ssid), app.palette),
                ]
                .spacing(6),
            );
        }
        list = list.push(entry);
    }
    column![
        cc_back("Wi-Fi"),
        cc_section(
            column![
                row![
                    cc_toggle(
                        app,
                        &app.cfg.icons.network,
                        "Wi-Fi",
                        app.data.cc_wifi,
                        Message::ToggleSetting("wifi")
                    ),
                    action_button("Scan", Message::WifiRescan, app.palette)
                ]
                .spacing(8),
                row![
                    text(app.data.network_detail.clone()).width(Length::Fill),
                    action_button("Disconnect", Message::WifiDisconnect, app.palette)
                ],
                scrollable(list).height(Length::Fixed(260.0)),
            ]
            .spacing(8),
            app.palette,
        ),
    ]
    .spacing(10)
    .into()
}

fn cc_sound_view(app: &App) -> Element<'_, Message> {
    column![
        cc_back("Sound"),
        cc_section(
            column![
                audio_slider(app, AudioDevice::Speaker),
                audio_slider(app, AudioDevice::Mic)
            ]
            .spacing(10),
            app.palette
        ),
        action_button("Open Mixer", Message::OpenPavucontrol, app.palette),
    ]
    .spacing(10)
    .into()
}

fn cc_notifications_view(app: &App) -> Element<'_, Message> {
    let mut list = column![].spacing(6);
    for notification in &app.data.notifications_history {
        let key = notification.key.clone();
        let dot: Element<'_, Message> = if notification.unread {
            text("●")
                .size(10)
                .color(app.palette.critical)
                .width(Length::Fixed(8.0))
                .into()
        } else {
            space().width(Length::Fixed(8.0)).into()
        };
        let mut entry = column![
            button(
                row![
                    dot,
                    column![
                        text(limit(&notification.summary, 34)),
                        text(limit(&notification.preview, 40)).color(app.palette.foreground_dim),
                    ]
                    .width(Length::Fill),
                    text(if notification.source == "active" {
                        "Now"
                    } else {
                        "History"
                    })
                    .size(10)
                    .color(app.palette.foreground_dim),
                ]
                .spacing(8),
            )
            .width(Length::Fill)
            .padding([7, 8])
            .style(move |_, status| active_row_style(
                app.palette,
                status,
                notification.unread || notification.urgency == "critical"
            ))
            .on_press(Message::ToggleNotification(key.clone()))
        ];
        if app.ui.notification_expanded_id == notification.key {
            let body = if notification.body.is_empty() {
                "No details"
            } else {
                &notification.body
            };
            entry = entry.push(
                container(text(body.to_string()).color(app.palette.foreground_dim))
                    .padding([9, 24]),
            );
        }
        list = list.push(entry);
    }
    column![
        cc_back("Notifications"),
        row![
            text(format!(
                "{} notifications",
                app.data.notifications_history_count
            ))
            .width(Length::Fill),
            action_button("Clear", Message::ClearNotifications, app.palette)
        ],
        cc_section(scrollable(list).height(Length::Fixed(360.0)), app.palette),
    ]
    .spacing(10)
    .into()
}

fn cc_session_view(app: &App) -> Element<'_, Message> {
    column![
        cc_back("Power"),
        cc_section(
            column![
                session_row(app, &app.cfg.icons.lock, "Lock", "lock"),
                session_row(app, &app.cfg.icons.suspend, "Suspend", "suspend"),
                session_row(app, &app.cfg.icons.logout, "Logout", "logout"),
                session_row(app, &app.cfg.icons.reboot, "Reboot", "reboot"),
                session_row(app, &app.cfg.icons.shutdown, "Shutdown", "shutdown"),
            ]
            .spacing(4),
            app.palette,
        ),
    ]
    .spacing(10)
    .into()
}

fn cc_back(label: &str) -> Element<'_, Message> {
    row![
        button(text("‹").size(22))
            .padding([2, 8])
            .style(transparent_button)
            .on_press(Message::SetCcView(CcView::Home)),
        text(label).size(18),
    ]
    .spacing(8)
    .align_y(Alignment::Center)
    .into()
}

fn audio_slider(app: &App, device: AudioDevice) -> Element<'_, Message> {
    let data = match device {
        AudioDevice::Speaker => &app.data.audio_speaker,
        AudioDevice::Mic => &app.data.audio_mic,
    };
    let value = f32::from(data.value).clamp(0.0, 100.0);
    row![
        button(icon_path(&data.icon, Some(data.color), 20.0))
            .padding(6)
            .style(transparent_button)
            .on_press(Message::AudioToggle(device)),
        column![
            row![
                text(data.device.clone()).width(Length::Fill),
                text(data.percent.clone()).color(app.palette.foreground_dim)
            ],
            slider(0.0..=100.0, value, move |value| Message::AudioSet(
                device,
                value / 100.0
            )),
        ]
        .width(Length::Fill),
    ]
    .spacing(8)
    .align_y(Alignment::Center)
    .into()
}

fn brightness_slider(app: &App) -> Element<'_, Message> {
    row![
        icon_path(
            &app.cfg.icons.brightness,
            Some(app.palette.foreground),
            20.0
        ),
        column![
            row![
                text("Brightness").width(Length::Fill),
                text(app.data.brightness_text.clone()).color(app.palette.foreground_dim)
            ],
            slider(
                0.0..=100.0,
                app.data.brightness_value.clamp(0.0, 100.0),
                |value| Message::BrightnessSet(value / 100.0)
            ),
        ]
        .width(Length::Fill),
    ]
    .spacing(8)
    .align_y(Alignment::Center)
    .into()
}

fn session_row<'a>(
    app: &'a App,
    icon: &'a Path,
    label: &'static str,
    action: &'static str,
) -> Element<'a, Message> {
    button(
        row![
            icon_path(icon, Some(app.palette.foreground), 20.0),
            text(label)
        ]
        .spacing(10),
    )
    .width(Length::Fill)
    .padding([8, 10])
    .style(move |_, status| flat_button_style(app.palette, status))
    .on_press(Message::Session(action))
    .into()
}

fn calendar_view(app: &App) -> Element<'_, Message> {
    overlay_panel(
        calendar_panel(app),
        app.palette,
        Message::CloseCalendar,
        true,
    )
}

fn calendar_panel(app: &App) -> Element<'_, Message> {
    let today = Local::now().date_naive();
    let first = today.with_day(1).unwrap_or(today);
    let start_weekday = first.weekday().num_days_from_monday() as usize;
    let days = days_in_month(today.year(), today.month());
    let mut grid = column![].spacing(4);
    let mut header = row![].spacing(4);
    for label in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] {
        header = header.push(
            container(text(label).size(11).color(app.palette.foreground_dim))
                .width(Length::Fixed(38.0))
                .align_x(alignment::Horizontal::Center),
        );
    }
    grid = grid.push(header);
    let mut day = 1_u32;
    for week in 0..6 {
        let mut roww = row![].spacing(4);
        for weekday in 0..7 {
            if (week == 0 && weekday < start_weekday) || day > days {
                roww = roww.push(
                    container(space())
                        .width(Length::Fixed(38.0))
                        .height(Length::Fixed(28.0)),
                );
            } else {
                let is_today = day == today.day();
                let p = app.palette;
                roww = roww.push(
                    container(text(day.to_string()).color(if is_today {
                        p.on_primary
                    } else {
                        p.foreground
                    }))
                    .width(Length::Fixed(38.0))
                    .height(Length::Fixed(28.0))
                    .align_x(alignment::Horizontal::Center)
                    .align_y(alignment::Vertical::Center)
                    .style(move |_| {
                        container_style(
                            if is_today {
                                p.primary
                            } else {
                                Color::TRANSPARENT
                            },
                            if is_today {
                                p.primary
                            } else {
                                Color::TRANSPARENT
                            },
                            14.0,
                        )
                    }),
                );
                day += 1;
            }
        }
        grid = grid.push(roww);
    }
    column![
        text(format!("{} {}", today.format("%B"), today.year())).size(18),
        text(format!(
            "{}  {}",
            app.data.datetime_date, app.data.datetime_time
        ))
        .color(app.palette.foreground_dim),
        grid,
    ]
    .spacing(10)
    .into()
}

fn tray_icon_view<'a>(
    item: &'a TrayItem,
    fallback: &'a Path,
    color: Color,
) -> Element<'a, Message> {
    match item.icon.as_ref() {
        Some(TrayIcon::Image(handle)) => image(handle.clone())
            .width(Length::Fixed(20.0))
            .height(Length::Fixed(20.0))
            .into(),
        Some(TrayIcon::Svg(path)) => icon_path(path, None, 20.0),
        None => icon_path(fallback, Some(color), 20.0),
    }
}

fn tray_menu_view<'a>(
    address: &'a str,
    menu_path: &'a str,
    menu: &'a TrayMenu,
    p: Palette,
) -> Element<'a, Message> {
    let mut col = column![].spacing(2).padding(6).width(Length::Fixed(220.0));
    for item in menu.submenus.iter().filter(|item| item.visible) {
        col = col.push(tray_menu_item(address, menu_path, item, p, 0));
    }
    container(col)
        .style(move |_| container_style(p.surface_active, p.outline, 8.0))
        .into()
}

fn tray_menu_item<'a>(
    address: &'a str,
    menu_path: &'a str,
    item: &'a MenuItem,
    p: Palette,
    indent: u16,
) -> Element<'a, Message> {
    if item.menu_type == MenuType::Separator {
        return container(space())
            .height(Length::Fixed(1.0))
            .style(move |_| container_style(p.outline, p.outline, 0.0))
            .into();
    }
    let label = clean_menu_label(item.label.as_deref().unwrap_or(""));
    let prefix = match item.toggle_state {
        ToggleState::On => "✓ ",
        ToggleState::Off | ToggleState::Indeterminate => "",
    };
    let text_color = if item.enabled {
        p.foreground
    } else {
        p.foreground_dim
    };
    let mut content = column![
        button(text(format!("{prefix}{label}")).color(text_color))
            .width(Length::Fill)
            .padding([4, 10 + indent])
            .style(move |_, status| flat_button_style(p, status))
            .on_press_maybe(item.enabled.then(|| Message::TrayMenuItem {
                address: address.to_string(),
                menu_path: menu_path.to_string(),
                id: item.id
            }))
    ];
    for sub in item.submenu.iter().filter(|item| item.visible) {
        content = content.push(tray_menu_item(address, menu_path, sub, p, indent + 12));
    }
    content.into()
}

fn overlay_panel<'a>(
    content: Element<'a, Message>,
    p: Palette,
    close: Message,
    calendar: bool,
) -> Element<'a, Message> {
    let width = if calendar { 330.0 } else { 390.0 };
    let panel = container(content)
        .padding(12)
        .width(Length::Fixed(width))
        .style(move |_| container_style(p.surface, p.outline, 12.0));
    let aligned = container(panel)
        .width(Length::Fill)
        .height(Length::Fill)
        .align_x(alignment::Horizontal::Right)
        .align_y(alignment::Vertical::Top)
        .padding([42, 12]);
    stack(vec![
        mouse_area(
            container(space())
                .width(Length::Fill)
                .height(Length::Fill)
                .style(move |_| container_style(p.background, Color::TRANSPARENT, 0.0)),
        )
        .on_press(close)
        .into(),
        aligned.into(),
    ])
    .into()
}

fn cc_section<'a>(content: impl Into<Element<'a, Message>>, p: Palette) -> Element<'a, Message> {
    container(content)
        .padding(10)
        .style(move |_| container_style(p.surface_container, p.outline, 12.0))
        .into()
}

fn island<'a>(
    content: impl Into<Element<'a, Message>>,
    p: Palette,
) -> iced::widget::Container<'a, Message> {
    container(content)
        .padding([4, 6])
        .height(Length::Fixed(BAR_HEIGHT))
        .max_height(BAR_HEIGHT)
        .align_y(alignment::Vertical::Center)
        .style(move |_| container_style(p.surface, p.outline, 14.0))
}

fn label_pill<'a>(label: String, p: Palette) -> Element<'a, Message> {
    container(
        text(label)
            .size(12)
            .line_height(BAR_TEXT_LINE_HEIGHT)
            .color(p.foreground_dim),
    )
    .padding([2, 6])
    .into()
}

fn action_button<'a>(label: &'a str, message: Message, p: Palette) -> Element<'a, Message> {
    button(text(label))
        .padding([6, 10])
        .style(move |_, status| flat_button_style(p, status))
        .on_press(message)
        .into()
}

fn icon_path<'a>(path: &'a Path, color: Option<Color>, size: f32) -> Element<'a, Message> {
    if path.as_os_str().is_empty() {
        return text("·").size(size).into();
    }
    let extension = path
        .extension()
        .and_then(|ext| ext.to_str())
        .unwrap_or_default();
    if extension.eq_ignore_ascii_case("svg") {
        svg::Svg::from_path(path)
            .width(Length::Fixed(size))
            .height(Length::Fixed(size))
            .style(move |_, _| svg::Style { color })
            .into()
    } else {
        image(path)
            .width(Length::Fixed(size))
            .height(Length::Fixed(size))
            .into()
    }
}

fn container_style(
    background: Color,
    border: Color,
    radius: f32,
) -> iced::widget::container::Style {
    iced::widget::container::Style {
        text_color: None,
        background: Some(Background::Color(background)),
        border: Border {
            radius: radius.into(),
            width: if border.a > 0.0 { 1.0 } else { 0.0 },
            color: border,
        },
        ..Default::default()
    }
}

fn transparent_button(
    _theme: &Theme,
    _status: iced::widget::button::Status,
) -> iced::widget::button::Style {
    iced::widget::button::Style {
        background: None,
        text_color: Color::WHITE,
        ..Default::default()
    }
}

fn island_button_style(
    p: Palette,
    status: iced::widget::button::Status,
    active: bool,
) -> iced::widget::button::Style {
    let background = if active || matches!(status, iced::widget::button::Status::Hovered) {
        p.surface_hover
    } else {
        p.surface
    };
    iced::widget::button::Style {
        background: Some(Background::Color(background)),
        text_color: p.foreground,
        border: Border {
            radius: 14.0.into(),
            width: 1.0,
            color: if active { p.primary } else { p.outline },
        },
        ..Default::default()
    }
}

fn flat_button_style(
    p: Palette,
    status: iced::widget::button::Status,
) -> iced::widget::button::Style {
    let background = if matches!(
        status,
        iced::widget::button::Status::Hovered | iced::widget::button::Status::Pressed
    ) {
        p.surface_hover
    } else {
        p.surface_active
    };
    iced::widget::button::Style {
        background: Some(Background::Color(background)),
        text_color: p.foreground,
        border: Border {
            radius: 10.0.into(),
            width: 0.0,
            color: Color::TRANSPARENT,
        },
        ..Default::default()
    }
}

fn active_row_style(
    p: Palette,
    status: iced::widget::button::Status,
    active: bool,
) -> iced::widget::button::Style {
    let background = if active {
        p.surface_hover
    } else if matches!(
        status,
        iced::widget::button::Status::Hovered | iced::widget::button::Status::Pressed
    ) {
        p.surface_active
    } else {
        Color::TRANSPARENT
    };
    iced::widget::button::Style {
        background: Some(Background::Color(background)),
        text_color: p.foreground,
        border: Border {
            radius: 8.0.into(),
            width: 0.0,
            color: Color::TRANSPARENT,
        },
        ..Default::default()
    }
}

fn toggle_button_style(
    p: Palette,
    status: iced::widget::button::Status,
    active: bool,
) -> iced::widget::button::Style {
    let background = if active {
        p.surface_hover
    } else if matches!(
        status,
        iced::widget::button::Status::Hovered | iced::widget::button::Status::Pressed
    ) {
        p.surface_active
    } else {
        p.surface_container
    };
    iced::widget::button::Style {
        background: Some(Background::Color(background)),
        text_color: if active { p.primary } else { p.foreground },
        border: Border {
            radius: 12.0.into(),
            width: 1.0,
            color: if active { p.primary } else { p.outline },
        },
        ..Default::default()
    }
}

#[derive(Debug, Clone, Copy)]
struct BatteryRing {
    value: f32,
    color: Color,
    track: Color,
}

impl<Message> canvas::Program<Message> for BatteryRing {
    type State = ();

    fn draw(
        &self,
        _state: &Self::State,
        renderer: &iced::Renderer,
        _theme: &Theme,
        bounds: Rectangle,
        _cursor: iced::mouse::Cursor,
    ) -> Vec<canvas::Geometry> {
        let mut frame = canvas::Frame::new(renderer, bounds.size());
        let center = Point::new(bounds.width / 2.0, bounds.height / 2.0);
        let radius = bounds.width.min(bounds.height) / 2.0 - 3.0;
        let track = CanvasPath::circle(center, radius);
        frame.stroke(
            &track,
            Stroke::default().with_width(3.0).with_color(self.track),
        );
        if self.value > 0.0 {
            let end = -std::f32::consts::FRAC_PI_2 + std::f32::consts::TAU * (self.value / 100.0);
            let path = CanvasPath::new(|builder| {
                builder.arc(path::Arc {
                    center,
                    radius,
                    start_angle: Radians(-std::f32::consts::FRAC_PI_2),
                    end_angle: Radians(end),
                });
            });
            frame.stroke(
                &path,
                Stroke::default()
                    .with_width(3.0)
                    .with_color(self.color)
                    .with_line_cap(LineCap::Round),
            );
        }
        vec![frame.into_geometry()]
    }
}

fn run_command_task(f: impl FnOnce() -> Result<()> + Send + 'static) -> Task<Message> {
    Task::perform(
        async move {
            let _ = f();
        },
        |_| Message::Noop,
    )
}

fn action_refresh(
    f: impl FnOnce() -> Result<()> + Send + 'static,
    domain: RefreshDomain,
) -> Task<Message> {
    Task::perform(
        async move {
            let _ = f();
            domain
        },
        Message::Refresh,
    )
}

fn session_task(cfg: Arc<Config>, action: &'static str) -> Task<Message> {
    run_command_task(move || match action {
        "lock" => {
            command(&cfg, &cfg.commands.lock_screen)
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()?;
            Ok(())
        }
        "suspend" => status(&cfg, &cfg.commands.systemctl, ["suspend"]),
        "logout" => status(
            &cfg,
            &cfg.commands.niri,
            ["msg", "action", "quit", "--skip-confirmation"],
        ),
        "reboot" => status(&cfg, &cfg.commands.systemctl, ["reboot"]),
        "shutdown" => status(&cfg, &cfg.commands.systemctl, ["poweroff"]),
        _ => Ok(()),
    })
}

fn bar_settings(output: &str) -> NewLayerShellSettings {
    NewLayerShellSettings {
        size: Some((0, 32)),
        layer: Layer::Top,
        anchor: Anchor::Top | Anchor::Left | Anchor::Right,
        exclusive_zone: Some(36),
        margin: Some((4, 0, 0, 0)),
        keyboard_interactivity: KeyboardInteractivity::None,
        output_option: output_option(output),
        events_transparent: false,
        namespace: Some("framework-eww-bar".to_string()),
    }
}

fn overlay_settings(
    output: &str,
    namespace: &str,
    keyboard_interactivity: KeyboardInteractivity,
) -> NewLayerShellSettings {
    NewLayerShellSettings {
        size: None,
        layer: Layer::Overlay,
        anchor: Anchor::Top | Anchor::Bottom | Anchor::Left | Anchor::Right,
        exclusive_zone: Some(-1),
        margin: None,
        keyboard_interactivity,
        output_option: output_option(output),
        events_transparent: false,
        namespace: Some(namespace.to_string()),
    }
}

fn output_option(output: &str) -> OutputOption {
    if output == "0" {
        OutputOption::None
    } else {
        OutputOption::OutputName(output.to_string())
    }
}

fn days_in_month(year: i32, month: u32) -> u32 {
    let next_month = if month == 12 {
        NaiveDate::from_ymd_opt(year + 1, 1, 1)
    } else {
        NaiveDate::from_ymd_opt(year, month + 1, 1)
    }
    .unwrap_or_else(|| Local::now().date_naive());
    next_month.pred_opt().map(|date| date.day()).unwrap_or(30)
}

fn clean_menu_label(label: &str) -> String {
    let mut out = String::with_capacity(label.len());
    let mut chars = label.chars().peekable();
    while let Some(ch) = chars.next() {
        if ch == '_' {
            if chars.peek() == Some(&'_') {
                chars.next();
                out.push('_');
            }
        } else {
            out.push(ch);
        }
    }
    out
}

fn limit(value: &str, chars: usize) -> String {
    let mut iter = value.chars();
    let mut out = String::new();
    for _ in 0..chars {
        match iter.next() {
            Some(ch) => out.push(ch),
            None => return out,
        }
    }
    if iter.next().is_some() {
        out.push('…');
    }
    out
}
