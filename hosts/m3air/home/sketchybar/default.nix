{ pkgs, ... }:

let
  colors = import ./colors.nix;

  # Plugin scripts
  appFont = pkgs.sketchybar-app-font;
  aerospace = import ./plugins/aerospace.nix { inherit pkgs colors appFont; };
  battery = import ./plugins/battery.nix { inherit pkgs colors; };
  inputMethod = import ./plugins/input-method.nix { inherit pkgs; };
  network = import ./plugins/network.nix { inherit pkgs; };
  mem = import ./plugins/mem.nix { inherit pkgs; };
  cpu = import ./plugins/cpu.nix { inherit pkgs; };

  # Bar-config string fragments
  leftItems = import ./items/left.nix { inherit colors aerospace; };
  rightItems = import ./items/right.nix {
    inherit
      colors
      battery
      inputMethod
      network
      mem
      cpu
      ;
  };

in
{
  programs.sketchybar = {
    enable = true;

    # Keep service disabled — aerospace launches sketchybar via after-startup-command
    service.enable = false;

    extraPackages = [
      pkgs.jq
      pkgs.bc
      pkgs.sketchybar-app-font
    ];

    config = ''
      #!/usr/bin/env bash

      # ── Bar ──────────────────────────────────────────────────────────────────────
      sketchybar \
        --bar \
          height=37 \
          position=top \
          padding_left=8 \
          padding_right=8 \
          margin=0 \
          y_offset=0 \
          corner_radius=0 \
          border_width=0 \
          blur_radius=30 \
          color=${colors.bg0} \
          shadow=off \
          topmost=window \
          font_smoothing=on \
          display=all

      # ── Defaults ─────────────────────────────────────────────────────────────────
      sketchybar \
        --default \
          updates=when_shown \
          icon.font="SF Pro:Semibold:13.0" \
          icon.color=${colors.fg} \
          icon.padding_left=6 \
          icon.padding_right=4 \
          label.font="SF Pro:Regular:13.0" \
          label.color=${colors.fg} \
          label.padding_left=0 \
          label.padding_right=6 \
          background.height=24 \
          background.corner_radius=6 \
          background.color=${colors.bg1} \
          background.drawing=on \
          padding_left=3 \
          padding_right=3

      # ── Custom events ─────────────────────────────────────────────────────────────
      sketchybar --add event aerospace_workspace_change
      sketchybar --add event aerospace_mode_change
      sketchybar --add event aerospace_focus_change

      ${leftItems}

      ${rightItems}

      # ── Final update ──────────────────────────────────────────────────────────────
      sketchybar --update
    '';
  };
}
