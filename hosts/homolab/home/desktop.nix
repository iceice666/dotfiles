{
  config,
  lib,
  pkgs,
  ...
}:

{
  xsession.enable = true;

  xdg.configFile."bspwm/bspwmrc" = {
    executable = true;
    text = ''
      #!${pkgs.bash}/bin/bash

      ${pkgs.bspwm}/bin/bspc monitor -d I II III IV V VI VII VIII IX X
      ${pkgs.bspwm}/bin/bspc config border_width 2
      ${pkgs.bspwm}/bin/bspc config window_gap 8
      ${pkgs.bspwm}/bin/bspc config split_ratio 0.52
      ${pkgs.bspwm}/bin/bspc config borderless_monocle true
      ${pkgs.bspwm}/bin/bspc config gapless_monocle true
      ${pkgs.bspwm}/bin/bspc config focus_follows_pointer true
    '';
  };

  xdg.configFile."sxhkd/sxhkdrc".text = ''
    super + Return
      ${pkgs.kitty}/bin/kitty

    super + n
      ${lib.getExe config.programs.zed-editor.package}

    super + b
      ${lib.getExe pkgs.helium-bin}

    super + Escape
      ${pkgs.procps}/bin/pkill -USR1 -x sxhkd

    super + alt + q
      ${pkgs.bspwm}/bin/bspc quit

    super + alt + r
      ${pkgs.bspwm}/bin/bspc wm -r

    super + w
      ${pkgs.bspwm}/bin/bspc node -c

    super + {h,j,k,l}
      ${pkgs.bspwm}/bin/bspc node -f {west,south,north,east}

    super + shift + {h,j,k,l}
      ${pkgs.bspwm}/bin/bspc node -s {west,south,north,east}

    super + {1-9,0}
      ${pkgs.bspwm}/bin/bspc desktop -f '^{1-9,10}'

    super + shift + {1-9,0}
      ${pkgs.bspwm}/bin/bspc node -d '^{1-9,10}'
  '';

  services.polybar = {
    enable = true;
    script = "polybar homolab &";
    settings = {
      "bar/homolab" = {
        width = "100%";
        height = 28;
        background = "#1d2021";
        foreground = "#ebdbb2";
        line.size = 2;
        padding.left = 1;
        padding.right = 1;
        module.margin = 1;
        font = [ "Cascadia Code:size=10;2" ];
        modules.left = "bspwm";
        modules.center = "date";
        modules.right = "cpu memory filesystem";
        wm.restack = "bspwm";
      };

      "module/bspwm" = {
        type = "internal/bspwm";
        label.focused = {
          text = "%name%";
          background = "#458588";
          padding = 1;
        };
        label.occupied = {
          text = "%name%";
          padding = 1;
        };
        label.empty = {
          text = "%name%";
          foreground = "#665c54";
          padding = 1;
        };
      };

      "module/date" = {
        type = "internal/date";
        interval = 5;
        date = "%Y-%m-%d";
        time = "%H:%M";
        label = "%date%  %time%";
      };

      "module/cpu" = {
        type = "internal/cpu";
        interval = 2;
        label = "CPU %percentage%%";
      };

      "module/memory" = {
        type = "internal/memory";
        interval = 2;
        label = "RAM %percentage_used%%";
      };

      "module/filesystem" = {
        type = "internal/fs";
        interval = 30;
        mount = "/";
        label.mounted = "ROOT %percentage_used%%";
      };
    };
  };

  programs.kitty = {
    enable = true;
    shellIntegration.enableFishIntegration = true;
    settings = {
      font_family = "Cascadia Code";
      font_size = 12;
      background = "#1d2021";
      foreground = "#ebdbb2";
      cursor = "#ebdbb2";
      selection_background = "#504945";
      enable_audio_bell = false;
      scrollback_lines = 10000;
      confirm_os_window_close = 0;
    };
  };

  # Homolab does not install the wallpaper-generated Themegen themes.
  programs.zed-editor.userSettings.theme = lib.mkForce "One Dark";
}
