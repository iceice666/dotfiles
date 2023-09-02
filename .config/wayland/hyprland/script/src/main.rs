use std::process::Command;

use hyprland::data::Workspaces;
use hyprland::event_listener::EventListenerMutable as EventListener;
use hyprland::prelude::*;

fn main() -> hyprland::Result<()> {
    let mut event_listener = EventListener::new();

    event_listener.add_workspace_change_handler(|id, _| {
        let mut data: Vec<(i32, String)> = Workspaces::get()
            .unwrap()
            .iter()
            .map(|item| (item.id, item.name.clone()))
            .collect();

        data.sort_by(|a, b| a.0.cmp(&b.0));

        let data: Vec<String> = data.iter().map(|item| item.1.clone()).collect();

        let _ = Command::new("eww")
            .args([
                "-c",
                "/home/iceice666/.config/wayland/eww",
                "update",
                &format!("workspaces={:?}", data),
                &format!("current_workspace={}", id),
            ])
            .spawn();
    });

    event_listener.start_listener()
}
