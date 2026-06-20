use std::fs;
use std::os::unix::net::UnixDatagram as StdUnixDatagram;
use std::path::PathBuf;

use iced::futures::SinkExt;
use iced::{Subscription, stream};
use tokio::net::UnixDatagram;

use crate::helpers::runtime_dir;

const SOCKET_NAME: &str = "framework-bar.sock";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum RefreshDomain {
    All,
    Niri,
    Audio,
    Battery,
    Brightness,
    Perf,
    Media,
    Network,
    Datetime,
    Notifications,
    Theme,
    Toggles,
    Wifi,
}

pub fn refresh_socket_path() -> PathBuf {
    runtime_dir().join(SOCKET_NAME)
}

pub fn send_refresh(domain: RefreshDomain) {
    let path = refresh_socket_path();
    let Ok(socket) = StdUnixDatagram::unbound() else {
        return;
    };
    let _ = socket.send_to(domain.as_line().as_bytes(), path);
}

pub fn subscription() -> Subscription<RefreshDomain> {
    Subscription::run(|| {
        stream::channel(16, async |mut output| {
            let path = refresh_socket_path();
            let _ = fs::remove_file(&path);
            let Ok(socket) = UnixDatagram::bind(&path) else {
                return;
            };
            let mut buf = [0_u8; 128];
            loop {
                let Ok(size) = socket.recv(&mut buf).await else {
                    break;
                };
                let text = String::from_utf8_lossy(&buf[..size]);
                if let Some(domain) = RefreshDomain::parse(text.trim()) {
                    let _ = output.send(domain).await;
                }
            }
        })
    })
}

impl RefreshDomain {
    pub fn as_line(self) -> &'static str {
        match self {
            Self::All => "reload",
            Self::Niri => "refresh:niri",
            Self::Audio => "refresh:audio",
            Self::Battery => "refresh:battery",
            Self::Brightness => "refresh:brightness",
            Self::Perf => "refresh:perf",
            Self::Media => "refresh:media",
            Self::Datetime => "refresh:datetime",
            Self::Network => "refresh:network",
            Self::Notifications => "refresh:notifications",
            Self::Theme => "refresh:theme",
            Self::Toggles => "refresh:toggles",
            Self::Wifi => "refresh:wifi",
        }
    }

    pub fn parse(text: &str) -> Option<Self> {
        match text {
            "reload" | "refresh:all" => Some(Self::All),
            "refresh:niri" => Some(Self::Niri),
            "refresh:audio" => Some(Self::Audio),
            "refresh:battery" => Some(Self::Battery),
            "refresh:brightness" => Some(Self::Brightness),
            "refresh:perf" => Some(Self::Perf),
            "refresh:media" => Some(Self::Media),
            "refresh:network" => Some(Self::Network),
            "refresh:datetime" => Some(Self::Datetime),
            "refresh:notifications" | "notifications" => Some(Self::Notifications),
            "refresh:theme" => Some(Self::Theme),
            "refresh:toggles" => Some(Self::Toggles),
            "refresh:wifi" => Some(Self::Wifi),
            _ => None,
        }
    }
}
