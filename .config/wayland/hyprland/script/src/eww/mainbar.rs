use std::process::Command;

use hyprland::data::Workspaces;
use hyprland::event_listener::{EventListener, WindowEventData};
use hyprland::prelude::*;
use hyprland::shared::WorkspaceType;

fn worksapce_change(id: WorkspaceType) {
    let mut data: Vec<(i32, String)> = Workspaces::get()
        .unwrap()
        .iter()
        .map(|item| (item.id, item.name.clone()))
        .collect();

    data.sort_by(|a, b| a.0.cmp(&b.0));

    let data: Vec<String> = data.iter().map(|item| item.1.clone()).collect();

    let _ = Command::new("eww")
        .args([
            "update",
            &format!("mainbar-workspaces={:?}", data),
            &format!("mainbar-current_workspace={}", id),
        ])
        .spawn();
}

fn window_change(window: WindowEventData) {
    let class = window.window_class;
    let mut title = window.window_title;
    if class == "firefox" && title.len() > 20 {
        title.truncate(title.len() - 20);
    }

    let _ = Command::new("eww")
        .args([
            "update",
            &format!("mainbar-window_class={}", class),
            &format!("mainbar-window_title={}", title),
        ])
        .spawn();
}

pub async fn main() -> hyprland::Result<()> {
    let mut event_listener = EventListener::new();

    event_listener.add_workspace_change_handler(worksapce_change);

    event_listener.add_window_open_handler(|data| {
        window_change(WindowEventData {
            window_class: data.window_class,
            window_title: data.window_title,
            window_address: data.window_address,
        })
    });

    event_listener.add_active_window_change_handler(|data| window_change(data.unwrap()));

    event_listener.start_listener_async().await
}
