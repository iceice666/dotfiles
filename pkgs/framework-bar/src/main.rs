use std::{path::PathBuf, process::Stdio, sync::Arc};

use anyhow::Result;
use clap::{Parser, Subcommand};
use framework_bar::{
    AudioCommand, BrightnessCommand, MediaAction, NotificationCommand,
    collect::{
        audio::run_audio_command, brightness::run_brightness_command, media::run_media_command,
        notifications::run_notification_command,
    },
    config::read_config,
    helpers::{command, status},
    ipc::{RefreshDomain, send_refresh},
    run_daemon,
};

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

fn main() -> Result<()> {
    let cli = Cli::parse();
    let cfg = Arc::new(read_config(&cli.config_file)?);

    match cli.command {
        CliCommand::Daemon => run_daemon(cfg),
        CliCommand::Reload => {
            send_refresh(RefreshDomain::All);
            Ok(())
        }
        CliCommand::FocusWindow { id } => {
            status(
                &cfg,
                &cfg.commands.niri,
                ["msg", "action", "focus-window", "--id", &id],
            )?;
            send_refresh(RefreshDomain::Niri);
            Ok(())
        }
        CliCommand::OpenPavucontrol => {
            command(&cfg, &cfg.commands.pavucontrol)
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()?;
            Ok(())
        }
        CliCommand::Audio { command } => {
            run_audio_command(&cfg, command)?;
            send_refresh(RefreshDomain::Audio);
            Ok(())
        }
        CliCommand::Brightness { command } => {
            run_brightness_command(&cfg, command)?;
            send_refresh(RefreshDomain::Brightness);
            Ok(())
        }
        CliCommand::Media { action } => {
            run_media_command(&cfg, action)?;
            send_refresh(RefreshDomain::Media);
            Ok(())
        }
        CliCommand::Notifications { command } => {
            run_notification_command(&cfg, command)?;
            send_refresh(RefreshDomain::Notifications);
            Ok(())
        }
    }
}
