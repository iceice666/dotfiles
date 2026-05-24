{
  config,
  inputs,
  pkgs,
  username,
  homeDirectory,
  dotfiles,
  unstablePkgs,
  ...
}:

let
  desktopWallpaper = dotfiles + /assets/mzen.png;
in
{
  imports = [
    ./grub-theme.nix
    ./hardware-configuration.nix
    inputs.nirinit.nixosModules.nirinit
  ];

  networking.hostName = "framework";
  networking.networkmanager.enable = true;

  time.timeZone = "Asia/Taipei";
  i18n.defaultLocale = "en_US.UTF-8";

  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  nixpkgs.config.allowUnfree = true;

  boot = {
    kernelPackages = pkgs.linuxPackages_zen_7_0;
    kernelParams = [ "resume=/dev/disk/by-label/NIXOS_SWAP" ];
    resumeDevice = "/dev/disk/by-label/NIXOS_SWAP";

    loader = {
      efi.canTouchEfiVariables = true;
      grub = {
        enable = true;
        efiSupport = true;
        device = "nodev";
        extraEntries = ''
          if [ "$grub_platform" = "efi" ]; then
            fwsetup --is-supported
            if [ "$?" = 0 ]; then
              menuentry "UEFI Firmware Settings" --class efi $menuentry_id_option "uefi-firmware" {
                fwsetup
              }
            fi
          fi
        '';
      };
    };
  };

  hardware = {
    enableRedistributableFirmware = true;
    cpu.amd.updateMicrocode = true;
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
    graphics = {
      enable = true;
      enable32Bit = true;
    };
  };

  zramSwap.enable = false;
  swapDevices = [ { device = "/dev/disk/by-label/NIXOS_SWAP"; } ];
  powerManagement.enable = true;

  systemd.sleep.extraConfig = ''
    HibernateDelaySec=1h
  '';

  services = {
    accounts-daemon.enable = true;
    blueman.enable = true;
    dbus.enable = true;
    fprintd.enable = true;
    kanata = {
      enable = true;
      keyboards.framework.config = ''
        (defsrc
          caps ret
          lmet lalt
          ralt rctl)

        (deflayermap (default-layer)
          caps (tap-hold 50 140 esc lctl)
          ret (tap-hold 50 140 ret rctl)
          lmet lalt
          lalt lmet
          ralt rmet
          rctl ralt)
      '';
    };
    libinput.enable = true;
    logind.settings.Login = {
      HandleLidSwitch = "suspend-then-hibernate";
      HandleLidSwitchExternalPower = "suspend-then-hibernate";
      HandleLidSwitchDocked = "ignore";
    };
    gvfs.enable = true;
    power-profiles-daemon.enable = false;
    tailscale = {
      enable = true;
      openFirewall = true;
      extraSetFlags = [ "--accept-dns=true" ];
    };
    tlp = {
      enable = true;
      settings = {
        TLP_DEFAULT_MODE = "BAT";
        TLP_PERSISTENT_DEFAULT = 0;

        CPU_SCALING_GOVERNOR_ON_AC = "schedutil";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
        CPU_ENERGY_PERF_POLICY_ON_AC = "balance_performance";
        CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
        CPU_BOOST_ON_AC = 1;
        CPU_BOOST_ON_BAT = 0;
        PLATFORM_PROFILE_ON_AC = "balanced";
        PLATFORM_PROFILE_ON_BAT = "low-power";

        WIFI_PWR_ON_AC = "off";
        WIFI_PWR_ON_BAT = "on";
        SOUND_POWER_SAVE_ON_AC = 0;
        SOUND_POWER_SAVE_ON_BAT = 1;
        USB_AUTOSUSPEND = 1;
        USB_EXCLUDE_BTUSB = 1;

        START_CHARGE_THRESH_BAT0 = 75;
        STOP_CHARGE_THRESH_BAT0 = 80;
      };
    };
    upower.enable = true;

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };

    displayManager.sessionPackages = [ unstablePkgs.niri ];
    greetd = {
      enable = true;
      settings.default_session.user = "greeter";
    };
    nirinit = {
      enable = true;
      settings = {
        launch = {
          "com.mitchellh.ghostty" = "${pkgs.ghostty}/bin/ghostty";
        };

        skip.apps = [
          "dev.zed.Zed"
          "dev.iceice666.lazygit.repo86ff3035c73490ab"
          "equibop"
          "org.equicord.equibop"
          "zen"
        ];
      };
    };
  };

  security = {
    polkit.enable = true;
    rtkit.enable = true;
    pam.services = {
      greetd.fprintAuth = true;
      swaylock = {
        fprintAuth = true;
        unixAuth = true;
      };
      sudo.fprintAuth = true;
    };
  };

  programs = {
    fish.enable = true;
    dconf.enable = true;
    regreet = {
      enable = true;
      cageArgs = [
        "-s"
        "-m"
        "last"
      ];
      settings = {
        background = {
          path = toString desktopWallpaper;
          fit = "Cover";
        };
        GTK = {
          application_prefer_dark_theme = true;
          cursor_blink = true;
        };
        commands = {
          reboot = [
            "systemctl"
            "reboot"
          ];
          poweroff = [
            "systemctl"
            "poweroff"
          ];
        };
        appearance.greeting_msg = username;
        widget.clock = {
          format = "%a %H:%M";
          resolution = "500ms";
          label_width = 150;
        };
      };
      extraCss = ''
        window {
          background: transparent;
        }

        box,
        grid {
          border-radius: 16px;
        }

        entry,
        button,
        combobox,
        menubutton {
          border-radius: 10px;
        }

        entry {
          background-color: rgba(23, 23, 23, 0.54);
          border-color: rgba(255, 214, 224, 0.32);
          color: #f8fafc;
        }

        entry:focus {
          background-color: rgba(23, 23, 23, 0.74);
          border-color: rgba(255, 214, 224, 0.86);
          box-shadow: 0 0 28px rgba(255, 214, 224, 0.34);
        }
      '';
    };
  };

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    config.common.default = "*";
    extraPortals = with pkgs; [
      xdg-desktop-portal-gnome
      xdg-desktop-portal-gtk
    ];
  };

  environment.systemPackages =
    with pkgs;
    [
      git
      cage
      fprintd
      regreet
      networkmanagerapplet
    ]
    ++ [ unstablePkgs.just ];

  fonts.packages = with pkgs; [
    cascadia-code
    sarasa-gothic
    noto-fonts
    noto-fonts-color-emoji
  ];

  users = {
    mutableUsers = false;
    users.${username} = {
      isNormalUser = true;
      description = "Brian Duan";
      home = homeDirectory;
      extraGroups = [
        "wheel"
        "networkmanager"
        "video"
        "audio"
        "input"
        "plugdev"
      ];
      shell = pkgs.fish;
      hashedPassword = "$y$j9T$fbTjrWvTrGjiwdrOngS7r/$R7YM5G5.sAkwmaWVR3aeMQyjP0ILHAOZXsg9SoAmCe5";
    };

    users.root = {
      hashedPassword = "$y$j9T$pdHphuflshVqXSrSyPiqF.$YpuXSNnoqNDG6RXzDy3p/IU5aAgSzOHSvYUMloQ/rb/";
    };
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    sharedModules = [ inputs.sops-nix.homeManagerModules.sops ];
    extraSpecialArgs = {
      inherit
        username
        homeDirectory
        dotfiles
        unstablePkgs
        ;
    };
    users.${username} = import ../home;
  };

  system.stateVersion = "25.11";
}
