{
  pkgs,
  desktopWallpaper,
  ...
}:

let
  niriConfig = builtins.replaceStrings [ "@wallpaper@" ] [ (toString desktopWallpaper) ] (
    builtins.readFile ./niri-config.kdl
  );
in
{
  home.packages = with pkgs; [
    adwaita-icon-theme
    brightnessctl
    ghostty
    grim
    imv
    libnotify
    mpv
    nautilus
    noto-fonts
    noto-fonts-color-emoji
    overskride
    papirus-icon-theme
    pavucontrol
    playerctl
    slurp
    swappy
    swaybg
    wev
    wf-recorder
    wl-clipboard
    wlr-randr
    xdg-desktop-portal-gnome
    xdg-desktop-portal-gtk
    nerd-fonts.caskaydia-cove
  ];

  fonts.fontconfig.enable = true;

  gtk = {
    enable = true;
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
  };

  qt = {
    enable = true;
    platformTheme.name = "gtk";
    style.name = "adwaita-dark";
  };

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    XDG_CURRENT_DESKTOP = "niri";
    XDG_SESSION_DESKTOP = "niri";
    XDG_SESSION_TYPE = "wayland";
  };

  xdg = {
    enable = true;

    dataFile = {
      "wayland-sessions/niri.desktop".source = "${pkgs.niri}/share/wayland-sessions/niri.desktop";
      "systemd/user/niri.service".source = "${pkgs.niri}/share/systemd/user/niri.service";
      "systemd/user/niri-shutdown.target".source = "${pkgs.niri}/share/systemd/user/niri-shutdown.target";
    };

    portal = {
      enable = true;
      configPackages = [ pkgs.niri ];
      extraPortals = [
        pkgs.xdg-desktop-portal-gnome
        pkgs.xdg-desktop-portal-gtk
      ];
    };

    terminal-exec = {
      enable = true;
      settings.default = [ "com.mitchellh.ghostty.desktop" ];
    };
  };

  home.file.".config/niri/config.kdl".text = niriConfig;

  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        terminal = "ghostty";
        layer = "overlay";
        width = 48;
        lines = 12;
        tabs = 4;
        font = "CaskaydiaCove Nerd Font:size=14";
        icon-theme = "Papirus-Dark";
      };
      colors = {
        background = "171717f2";
        text = "e5e5e5ff";
        match = "93c5fdff";
        selection = "334155ff";
        selection-text = "ffffffff";
        border = "60a5faff";
      };
      border = {
        width = 2;
        radius = 8;
      };
    };
  };

  programs.swaylock = {
    enable = true;
    settings = {
      color = "171717";
      font = "CaskaydiaCove Nerd Font";
      indicator-radius = 120;
      indicator-thickness = 8;
      ring-color = "3b82f6";
      key-hl-color = "93c5fd";
      line-color = "00000000";
      inside-color = "171717cc";
      separator-color = "00000000";
    };
  };

  programs.waybar = {
    enable = true;
    systemd.enable = false;
    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 32;
      spacing = 8;
      modules-left = [
        "niri/workspaces"
        "niri/window"
      ];
      modules-center = [ "clock" ];
      modules-right = [
        "tray"
        "network"
        "pulseaudio"
        "battery"
      ];

      "niri/workspaces" = {
        format = "{index}";
        disable-scroll = false;
      };
      "niri/window".format = "{}";
      clock = {
        format = "{:%a %b %d  %H:%M}";
        tooltip-format = "{:%Y-%m-%d}";
      };
      network = {
        format-wifi = "{essid}";
        format-ethernet = "wired";
        format-disconnected = "offline";
        tooltip-format = "{ifname}";
      };
      pulseaudio = {
        format = "{volume}%";
        format-muted = "muted";
        on-click = "pavucontrol";
      };
      battery = {
        format = "{capacity}%";
        states = {
          warning = 30;
          critical = 15;
        };
      };
      tray.spacing = 8;
    };
    style = ''
      * {
        border: 0;
        border-radius: 0;
        font-family: "CaskaydiaCove Nerd Font", "Noto Sans", sans-serif;
        font-size: 13px;
        min-height: 0;
      }

      window#waybar {
        background: rgba(23, 23, 23, 0.92);
        color: #e5e5e5;
      }

      #workspaces button {
        color: #a3a3a3;
        padding: 0 8px;
      }

      #workspaces button.active {
        color: #ffffff;
        background: #2563eb;
      }

      #window,
      #clock,
      #tray,
      #network,
      #pulseaudio,
      #battery {
        padding: 0 10px;
      }

      #battery.warning {
        color: #facc15;
      }

      #battery.critical {
        color: #ef4444;
      }
    '';
  };

  services = {
    blueman-applet.enable = true;
    gnome-keyring.enable = true;
    network-manager-applet.enable = true;

    mako = {
      enable = true;
      settings = {
        anchor = "top-right";
        width = 360;
        height = 120;
        margin = "12";
        padding = "12";
        border-size = 2;
        border-radius = 8;
        background-color = "#171717f2";
        text-color = "#e5e5e5ff";
        border-color = "#60a5faff";
        default-timeout = 7000;
        font = "Noto Sans 12";
        icons = true;
        max-icon-size = 48;
      };
    };

    swayidle = {
      enable = true;
      timeouts = [
        {
          timeout = 300;
          command = "${pkgs.swaylock}/bin/swaylock -f";
        }
        {
          timeout = 600;
          command = "${pkgs.niri}/bin/niri msg action power-off-monitors";
          resumeCommand = "${pkgs.niri}/bin/niri msg action power-on-monitors";
        }
      ];
      events = [
        {
          event = "before-sleep";
          command = "${pkgs.swaylock}/bin/swaylock -f";
        }
      ];
    };
  };
}
