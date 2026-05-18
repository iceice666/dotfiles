{
  config,
  inputs,
  pkgs,
  username,
  homeDirectory,
  dotfiles,
  themegenCache,
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

  services = {
    accounts-daemon.enable = true;
    blueman.enable = true;
    dbus.enable = true;
    fprintd.enable = true;
    kanata = {
      enable = true;
      keyboards.framework.config = ''
        (defsrc
          caps)

        (deflayermap (default-layer)
          caps (tap-hold 100 150 esc lctl))
      '';
    };
    libinput.enable = true;
    gvfs.enable = true;

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

  environment.systemPackages = with pkgs; [
    git
    just
    vim
    cage
    fprintd
    regreet
    networkmanagerapplet
  ];

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
        themegenCache
        unstablePkgs
        ;
    };
    users.${username} = import ../home;
  };

  system.stateVersion = "25.11";
}
