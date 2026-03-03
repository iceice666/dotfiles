use iced::widget::{column, container, row, rule, scrollable, space, text};
use iced::{
    alignment, keyboard, theme, window, Background, Border, Color, Element, Event, Length,
    Subscription, Task, Theme,
};
use std::path::PathBuf;
use std::time::{Duration, Instant};
use toml::Value;

#[derive(Debug)]
struct Keymap {
    os: String,
    modes: Vec<Mode>,
}

#[derive(Debug)]
struct Mode {
    name: String,
    bindings: Vec<Binding>,
}

#[derive(Debug)]
struct Binding {
    keys: String,
    action: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum KeyTokenKind {
    Modifier,
    Key,
}

#[derive(Debug, Clone)]
struct KeyToken {
    label: String,
    kind: KeyTokenKind,
}

#[derive(Debug)]
struct HelpApp {
    keymap: Keymap,
    had_focus: bool,
    opacity: f32,
    target_opacity: f32,
}

#[derive(Debug, Clone)]
enum Message {
    Event(Event),
    Tick(Instant),
}

fn config_paths() -> Vec<PathBuf> {
    let home = dirs::home_dir().expect("could not determine home directory");
    vec![
        home.join(".aerospace.toml"),
        home.join(".config")
            .join("aerospace")
            .join("aerospace.toml"),
    ]
}

fn mode_order_key(name: &str) -> u8 {
    match name {
        "main" => 0,
        "resize" => 1,
        "monitor" => 2,
        "service" => 3,
        _ => 4,
    }
}

fn title_case(text: &str) -> String {
    let mut chars = text.chars();
    match chars.next() {
        None => String::new(),
        Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
    }
}

fn parse_binding_action(value: &Value) -> Option<String> {
    match value {
        Value::String(command) => {
            if command.starts_with("exec-and-forget") && command.contains("aerospace-help") {
                Some("Show this help".to_string())
            } else {
                Some(command.clone())
            }
        }
        Value::Array(commands) => {
            let as_strings: Vec<&str> = commands.iter().filter_map(Value::as_str).collect();
            if as_strings.is_empty() {
                return None;
            }

            if as_strings
                .iter()
                .any(|cmd| cmd.starts_with("exec-and-forget") && cmd.contains("aerospace-help"))
            {
                return Some("Show this help".to_string());
            }

            if let Some(non_exec) = as_strings
                .iter()
                .find(|cmd| !cmd.starts_with("exec-and-forget"))
            {
                return Some((*non_exec).to_string());
            }

            Some(as_strings[0].to_string())
        }
        _ => None,
    }
}

fn parse_mode(mode_name: &str, mode_value: &Value) -> Option<Mode> {
    let bindings_table = mode_value.get("binding")?.as_table()?;
    let bindings = bindings_table
        .iter()
        .filter_map(|(keys, action)| {
            parse_binding_action(action).map(|parsed_action| Binding {
                keys: keys.clone(),
                action: parsed_action,
            })
        })
        .collect::<Vec<_>>();

    if bindings.is_empty() {
        return None;
    }

    Some(Mode {
        name: title_case(mode_name),
        bindings,
    })
}

fn load_keymap() -> Keymap {
    let mut parse_errors = Vec::new();

    for path in config_paths() {
        if !path.exists() {
            continue;
        }

        let data = match std::fs::read_to_string(&path) {
            Ok(data) => data,
            Err(err) => {
                parse_errors.push(format!("Failed to read {}: {err}", path.display()));
                continue;
            }
        };

        let parsed = match data.parse::<Value>() {
            Ok(parsed) => parsed,
            Err(err) => {
                parse_errors.push(format!("Failed to parse {}: {err}", path.display()));
                continue;
            }
        };

        let mode_table = match parsed.get("mode").and_then(Value::as_table) {
            Some(table) => table,
            None => {
                parse_errors.push(format!(
                    "Failed to parse {}: missing [mode] table",
                    path.display()
                ));
                continue;
            }
        };

        let mut mode_names = mode_table.keys().cloned().collect::<Vec<_>>();
        mode_names.sort_by(|a, b| {
            mode_order_key(a)
                .cmp(&mode_order_key(b))
                .then_with(|| a.cmp(b))
        });

        let modes = mode_names
            .iter()
            .filter_map(|name| {
                mode_table
                    .get(name)
                    .and_then(|value| parse_mode(name, value))
            })
            .collect::<Vec<_>>();

        if !modes.is_empty() {
            return Keymap {
                os: "macos".to_string(),
                modes,
            };
        }

        parse_errors.push(format!(
            "Failed to parse {}: no bindings found under [mode.*.binding]",
            path.display()
        ));
    }

    if !parse_errors.is_empty() {
        for error in parse_errors {
            eprintln!("{error}");
        }
    } else {
        eprintln!(
            "Failed to locate AeroSpace config. Checked ~/.aerospace.toml and ~/.config/aerospace/aerospace.toml"
        );
    }

    std::process::exit(1);
}

fn linux_stub_keymap() -> Keymap {
    Keymap {
        os: "linux".to_string(),
        modes: vec![Mode {
            name: "Linux Stub".to_string(),
            bindings: vec![
                Binding {
                    keys: "Esc".to_string(),
                    action: "Close overlay".to_string(),
                },
                Binding {
                    keys: "Q".to_string(),
                    action: "Close overlay".to_string(),
                },
                Binding {
                    keys: "N/A".to_string(),
                    action: "Linux support is currently a stub".to_string(),
                },
            ],
        }],
    }
}

fn boot() -> HelpApp {
    let keymap = if cfg!(target_os = "linux") {
        linux_stub_keymap()
    } else {
        load_keymap()
    };

    HelpApp {
        keymap,
        had_focus: false,
        opacity: 0.0,
        target_opacity: 1.0,
    }
}

#[cfg(target_os = "macos")]
fn configure_activation_policy() {
    use objc2::MainThreadMarker;
    use objc2_app_kit::{NSApplication, NSApplicationActivationPolicy};

    if let Some(main_thread) = MainThreadMarker::new() {
        let app = NSApplication::sharedApplication(main_thread);
        app.setActivationPolicy(NSApplicationActivationPolicy::Accessory);
    }
}

#[cfg(not(target_os = "macos"))]
fn configure_activation_policy() {}

fn title(state: &HelpApp) -> String {
    match state.keymap.os.as_str() {
        "macos" => "AeroSpace Keybindings".to_string(),
        "linux" => "Window Manager Keybindings".to_string(),
        _ => "Keybindings".to_string(),
    }
}

fn theme(_state: &HelpApp) -> Theme {
    Theme::TokyoNight
}

fn tint(mut color: Color, opacity: f32) -> Color {
    color.a *= opacity;
    color
}

fn app_style(state: &HelpApp, _theme: &Theme) -> theme::Style {
    theme::Style {
        background_color: Color::TRANSPARENT,
        text_color: tint(Color::from_rgb8(240, 240, 245), state.opacity),
    }
}

fn subscription(_state: &HelpApp) -> Subscription<Message> {
    Subscription::batch(vec![
        iced::event::listen().map(Message::Event),
        iced::time::every(Duration::from_millis(16)).map(Message::Tick),
    ])
}

fn should_close_for_key(key: &keyboard::Key) -> bool {
    match key {
        keyboard::Key::Named(keyboard::key::Named::Escape) => true,
        keyboard::Key::Character(value) => value.eq_ignore_ascii_case("q"),
        _ => false,
    }
}

fn update(state: &mut HelpApp, message: Message) -> Task<Message> {
    match message {
        Message::Event(Event::Keyboard(keyboard::Event::KeyPressed { key, .. })) => {
            if should_close_for_key(&key) {
                state.target_opacity = 0.0;
            }
        }
        Message::Event(Event::Window(window::Event::Focused)) => {
            state.had_focus = true;
        }
        Message::Event(Event::Window(window::Event::Unfocused)) => {
            if state.had_focus {
                state.target_opacity = 0.0;
            }
        }
        Message::Tick(_now) => {
            let speed = 0.12;

            if state.opacity < state.target_opacity {
                state.opacity = (state.opacity + speed).min(state.target_opacity);
            } else if state.opacity > state.target_opacity {
                state.opacity = (state.opacity - speed).max(state.target_opacity);
            }

            if state.target_opacity == 0.0 && state.opacity <= 0.0 {
                return iced::exit();
            }
        }
        _ => {}
    }

    Task::none()
}

fn translate_keys(raw: &str, os: &str) -> Vec<KeyToken> {
    let parts: Vec<&str> = raw
        .split(|ch| ch == '+' || ch == '-')
        .map(str::trim)
        .collect();
    let mut out = Vec::new();

    for part in parts {
        if part.is_empty() {
            continue;
        }

        let lower = part.to_lowercase();
        let token = match (os, lower.as_str()) {
            (_, "alt" | "opt" | "option") => KeyToken {
                label: "⌥".to_string(),
                kind: KeyTokenKind::Modifier,
            },
            (_, "shift") => KeyToken {
                label: "⇧".to_string(),
                kind: KeyTokenKind::Modifier,
            },
            (_, "cmd" | "super") => KeyToken {
                label: if os == "linux" {
                    "◆".to_string()
                } else {
                    "⌘".to_string()
                },
                kind: KeyTokenKind::Modifier,
            },
            (_, "ctrl") => KeyToken {
                label: "⌃".to_string(),
                kind: KeyTokenKind::Modifier,
            },
            (_, "enter" | "return") => KeyToken {
                label: "↩".to_string(),
                kind: KeyTokenKind::Key,
            },
            (_, "esc" | "escape") => KeyToken {
                label: "⎋".to_string(),
                kind: KeyTokenKind::Key,
            },
            (_, "tab") => KeyToken {
                label: "⇥".to_string(),
                kind: KeyTokenKind::Key,
            },
            (_, "minus") => KeyToken {
                label: "-".to_string(),
                kind: KeyTokenKind::Key,
            },
            (_, "equal") => KeyToken {
                label: "=".to_string(),
                kind: KeyTokenKind::Key,
            },
            (_, "comma") => KeyToken {
                label: ",".to_string(),
                kind: KeyTokenKind::Key,
            },
            (_, "period") => KeyToken {
                label: ".".to_string(),
                kind: KeyTokenKind::Key,
            },
            (_, "slash") => KeyToken {
                label: "/".to_string(),
                kind: KeyTokenKind::Key,
            },
            (_, "semicolon") => KeyToken {
                label: ";".to_string(),
                kind: KeyTokenKind::Key,
            },
            (_, "backspace" | "delete") => KeyToken {
                label: "⌫".to_string(),
                kind: KeyTokenKind::Key,
            },
            (_, "space") => KeyToken {
                label: "␣".to_string(),
                kind: KeyTokenKind::Key,
            },
            _ => KeyToken {
                label: {
                    let mut chars = part.chars();
                    match chars.next() {
                        None => String::new(),
                        Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
                    }
                },
                kind: KeyTokenKind::Key,
            },
        };
        out.push(token);
    }

    out
}

fn keycap(token: KeyToken, opacity: f32) -> Element<'static, Message> {
    let (foreground, background, border, size) = if token.kind == KeyTokenKind::Modifier {
        (
            tint(Color::from_rgb8(255, 255, 255), opacity),
            tint(Color::from_rgba8(255, 255, 255, 0.15), opacity),
            tint(Color::from_rgba8(255, 255, 255, 0.25), opacity),
            16,
        )
    } else {
        (
            tint(Color::from_rgb8(240, 240, 240), opacity),
            tint(Color::from_rgba8(255, 255, 255, 0.08), opacity),
            tint(Color::from_rgba8(255, 255, 255, 0.15), opacity),
            15,
        )
    };

    container(
        text(token.label)
            .size(size)
            .color(foreground)
            .font(iced::Font::DEFAULT),
    )
    .padding([3, 9])
    .style(move |_theme| container::Style {
        background: Some(Background::Color(background)),
        border: Border {
            color: border,
            width: 1.0,
            radius: 6.0.into(),
        },
        ..Default::default()
    })
    .into()
}

fn mode_card<'a>(mode: &'a Mode, os: &'a str, opacity: f32) -> Element<'a, Message> {
    let mut bindings = column![].spacing(8);

    for pair in mode.bindings.chunks(2) {
        let mut binding_pair = row![].spacing(6).width(Length::Fill);

        for binding in pair {
            let mut key_row = row![]
                .spacing(4)
                .align_y(alignment::Vertical::Center)
                .width(Length::Shrink);

            let translated_keys = translate_keys(&binding.keys, os);
            for (index, token) in translated_keys.into_iter().enumerate() {
                if index > 0 {
                    key_row = key_row.push(
                        text("+")
                            .size(12)
                            .color(tint(Color::from_rgba8(255, 255, 255, 0.6), opacity)),
                    );
                }
                key_row = key_row.push(keycap(token, opacity));
            }

            let cell = container(
                row![
                    container(key_row).width(Length::Fixed(176.0)),
                    container(
                        text(&binding.action)
                            .size(17)
                            .color(tint(Color::from_rgba8(255, 255, 255, 0.9), opacity))
                    )
                    .width(Length::Fill)
                ]
                .spacing(8)
                .align_y(alignment::Vertical::Center)
                .width(Length::Fill),
            )
            .padding([8, 10])
            .width(Length::FillPortion(1))
            .style(move |_theme| container::Style {
                background: Some(Background::Color(tint(
                    Color::from_rgba8(255, 255, 255, 0.05),
                    opacity,
                ))),
                border: Border {
                    color: tint(Color::from_rgba8(255, 255, 255, 0.1), opacity),
                    width: 1.0,
                    radius: 8.0.into(),
                },
                ..Default::default()
            });

            binding_pair = binding_pair.push(cell);
        }

        if pair.len() == 1 {
            binding_pair = binding_pair.push(space().width(Length::FillPortion(1)));
        }

        bindings = bindings.push(binding_pair);
    }

    container(
        column![
            text(&mode.name)
                .size(24)
                .color(tint(Color::from_rgba8(255, 255, 255, 0.95), opacity)),
            bindings
        ]
        .spacing(10),
    )
    .padding([14, 16])
    .width(Length::Fill)
    .style(move |_theme| container::Style {
        background: Some(Background::Color(tint(
            Color::from_rgba8(30, 30, 35, 0.4),
            opacity,
        ))),
        border: Border {
            color: tint(Color::from_rgba8(255, 255, 255, 0.15), opacity),
            width: 1.0,
            radius: 12.0.into(),
        },
        ..Default::default()
    })
    .into()
}

fn view(state: &HelpApp) -> Element<'_, Message> {
    let mut cards = column![].spacing(14).padding([0, 2]);

    for mode in &state.keymap.modes {
        cards = cards.push(mode_card(mode, &state.keymap.os, state.opacity));
    }

    let header = row![
        text(title(state))
            .size(34)
            .color(tint(Color::from_rgba8(255, 255, 255, 1.0), state.opacity)),
        space().width(Length::Fill),
        text("Press Q or Esc to close")
            .size(16)
            .color(tint(Color::from_rgba8(255, 255, 255, 0.5), state.opacity))
    ]
    .align_y(alignment::Vertical::Center);

    let divider = rule::horizontal(1).style(|_theme| rule::Style {
        color: tint(Color::from_rgba8(255, 255, 255, 0.15), state.opacity),
        radius: 0.0.into(),
        fill_mode: rule::FillMode::Full,
        snap: false,
    });

    let content = container(
        column![
            header,
            divider,
            scrollable(cards)
                .direction(scrollable::Direction::Vertical(scrollable::Scrollbar::new()))
        ]
        .spacing(10)
        .padding(16),
    )
    .max_width(1020)
    .width(Length::Fill)
    .center_x(Length::Fill);

    container(content)
        .width(Length::Fill)
        .height(Length::Fill)
        .padding([12, 20])
        .style(|_theme| container::Style {
            background: Some(Background::Color(tint(
                Color::from_rgba8(0, 0, 0, 0.45),
                state.opacity,
            ))),
            ..Default::default()
        })
        .into()
}

fn main() -> iced::Result {
    configure_activation_policy();

    iced::application(boot, update, view)
        .title(title)
        .theme(theme)
        .style(app_style)
        .subscription(subscription)
        .window(window::Settings {
            size: iced::Size::new(1140.0, 760.0),
            position: window::Position::Centered,
            maximized: false,
            fullscreen: false,
            resizable: false,
            transparent: true,
            blur: true,
            decorations: false,
            level: window::Level::AlwaysOnTop,
            ..window::Settings::default()
        })
        .run()
}
