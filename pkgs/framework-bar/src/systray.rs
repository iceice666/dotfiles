use std::collections::BTreeMap;
use std::path::PathBuf;

use iced::futures::SinkExt;
use iced::widget::image;
use iced::{Subscription, stream};
use system_tray::client::{ActivateRequest, Client, Event, UpdateEvent};
use system_tray::data::apply_menu_diffs;
use system_tray::item::{IconPixmap, StatusNotifierItem};
use system_tray::menu::TrayMenu;

use crate::icons::IconResolver;

#[derive(Debug, Clone)]
pub enum TrayEvent {
    Snapshot(Vec<(String, StatusNotifierItem, Option<TrayMenu>)>),
    Add(String, Box<StatusNotifierItem>),
    Update(String, UpdateEvent),
    Remove(String),
}

#[derive(Debug, Clone)]
pub struct TrayItem {
    pub address: String,
    pub item: StatusNotifierItem,
    pub menu: Option<TrayMenu>,
    pub icon: Option<TrayIcon>,
}

#[derive(Debug, Clone)]
pub enum TrayIcon {
    Image(image::Handle),
    Svg(PathBuf),
}

pub type TrayItems = BTreeMap<String, TrayItem>;

pub fn subscription() -> Subscription<TrayEvent> {
    Subscription::run(|| {
        stream::channel(64, async |mut output| {
            loop {
                let Ok(client) = Client::new().await else {
                    tokio::time::sleep(std::time::Duration::from_secs(5)).await;
                    continue;
                };
                let mut rx = client.subscribe();
                let snapshot = client
                    .items()
                    .lock()
                    .expect("tray item snapshot lock")
                    .iter()
                    .map(|(address, (item, menu))| (address.clone(), item.clone(), menu.clone()))
                    .collect::<Vec<_>>();
                let _ = output.send(TrayEvent::Snapshot(snapshot)).await;

                loop {
                    match rx.recv().await {
                        Ok(Event::Add(address, item)) => {
                            let _ = output.send(TrayEvent::Add(address, item)).await;
                        }
                        Ok(Event::Update(address, event)) => {
                            let _ = output.send(TrayEvent::Update(address, event)).await;
                        }
                        Ok(Event::Remove(address)) => {
                            let _ = output.send(TrayEvent::Remove(address)).await;
                        }
                        Err(_) => break,
                    }
                }
            }
        })
    })
}

pub fn apply_event(items: &mut TrayItems, resolver: &mut IconResolver, event: TrayEvent) {
    match event {
        TrayEvent::Snapshot(snapshot) => {
            items.clear();
            for (address, item, menu) in snapshot {
                insert_item(items, resolver, address, item, menu);
            }
        }
        TrayEvent::Add(address, item) => insert_item(items, resolver, address, *item, None),
        TrayEvent::Update(address, event) => {
            if let Some(entry) = items.get_mut(&address) {
                apply_update(entry, resolver, event);
            }
        }
        TrayEvent::Remove(address) => {
            items.remove(&address);
        }
    }
}

pub fn activate_default(address: String) -> iced::Task<()> {
    iced::Task::perform(
        async move {
            if let Ok(client) = Client::new().await {
                let _ = client
                    .activate(ActivateRequest::Default {
                        address,
                        x: 0,
                        y: 0,
                    })
                    .await;
            }
        },
        |_| (),
    )
}

pub fn activate_secondary(address: String) -> iced::Task<()> {
    iced::Task::perform(
        async move {
            if let Ok(client) = Client::new().await {
                let _ = client
                    .activate(ActivateRequest::Secondary {
                        address,
                        x: 0,
                        y: 0,
                    })
                    .await;
            }
        },
        |_| (),
    )
}

pub fn activate_menu(address: String, menu_path: String, submenu_id: i32) -> iced::Task<()> {
    iced::Task::perform(
        async move {
            if let Ok(client) = Client::new().await {
                let _ = client
                    .activate(ActivateRequest::MenuItem {
                        address,
                        menu_path,
                        submenu_id,
                    })
                    .await;
            }
        },
        |_| (),
    )
}

pub fn about_to_show(address: String, menu_path: String) -> iced::Task<()> {
    iced::Task::perform(
        async move {
            if let Ok(client) = Client::new().await {
                let _ = client.about_to_show_menuitem(address, menu_path, 0).await;
            }
        },
        |_| (),
    )
}

fn insert_item(
    items: &mut TrayItems,
    resolver: &mut IconResolver,
    address: String,
    item: StatusNotifierItem,
    menu: Option<TrayMenu>,
) {
    let icon = tray_icon(resolver, &item);
    items.insert(
        address.clone(),
        TrayItem {
            address,
            item,
            menu,
            icon,
        },
    );
}

fn apply_update(entry: &mut TrayItem, resolver: &mut IconResolver, event: UpdateEvent) {
    match event {
        UpdateEvent::AttentionIcon(icon_name) => entry.item.attention_icon_name = icon_name,
        UpdateEvent::Icon {
            icon_name,
            icon_pixmap,
        } => {
            entry.item.icon_name = icon_name;
            entry.item.icon_pixmap = icon_pixmap;
            entry.icon = tray_icon(resolver, &entry.item);
        }
        UpdateEvent::OverlayIcon(icon_name) => entry.item.overlay_icon_name = icon_name,
        UpdateEvent::Status(status) => entry.item.status = status,
        UpdateEvent::Title(title) => entry.item.title = title,
        UpdateEvent::Tooltip(tooltip) => entry.item.tool_tip = tooltip,
        UpdateEvent::Menu(menu) => entry.menu = Some(menu),
        UpdateEvent::MenuDiff(diff) => {
            if let Some(menu) = &mut entry.menu {
                apply_menu_diffs(menu, &diff);
            }
        }
        UpdateEvent::MenuConnect(menu) => entry.item.menu = Some(menu),
    }
}

fn tray_icon(resolver: &mut IconResolver, item: &StatusNotifierItem) -> Option<TrayIcon> {
    if let Some(name) = item.icon_name.as_deref().filter(|name| !name.is_empty())
        && let Some(path) = resolver.resolve_icon_name(name)
    {
        return Some(TrayIcon::Svg(path));
    }
    item.icon_pixmap
        .as_ref()
        .and_then(|pixmaps| {
            pixmaps
                .iter()
                .max_by_key(|pixmap| pixmap.width * pixmap.height)
        })
        .and_then(pixmap_handle)
        .map(TrayIcon::Image)
}

fn pixmap_handle(pixmap: &IconPixmap) -> Option<image::Handle> {
    let width = pixmap.width.try_into().ok()?;
    let height = pixmap.height.try_into().ok()?;
    let rgba = pixmap
        .pixels
        .chunks_exact(4)
        .flat_map(|chunk| [chunk[1], chunk[2], chunk[3], chunk[0]])
        .collect::<Vec<_>>();
    Some(image::Handle::from_rgba(width, height, rgba))
}
