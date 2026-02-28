{ ... }:

{
  home.file.".config/aerospace-swipe/config.json".text = builtins.toJSON {
    haptic = false;
    natural_swipe = true;
    wrap_around = true;
    skip_empty = true;
    fingers = 3;
  };

  programs.aerospace = {
    enable = true;
    launchd.enable = true;

    settings = {
      after-startup-command = [
        # JankyBorders has a built-in detection of already running process,
        # so it won't be run twice on AeroSpace restart
        "exec-and-forget /run/current-system/sw/bin/borders active_color=0xffe1e3e4 inactive_color=0xff494d64 width=5.0"
        "exec-and-forget /etc/profiles/per-user/iceice666/bin/aerospace-swipe"
        # "exec-and-forget /etc/profiles/per-user/iceice666/bin/sketchybar"
      ];

      # Notify sketchybar when the focused workspace changes
      exec-on-workspace-change = [
        "/bin/bash"
        "-c"
        "/run/current-system/sw/bin/sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE PREV_WORKSPACE=$AEROSPACE_PREV_WORKSPACE"
      ];

      enable-normalization-flatten-containers = true;
      enable-normalization-opposite-orientation-for-nested-containers = true;
      automatically-unhide-macos-hidden-apps = true;

      on-focused-monitor-changed = [ "move-mouse monitor-lazy-center" ];
      on-window-detected = [
        {
          "if" = {
            window-title-regex-substring = "登入";
          };
          run = [ "layout floating" ];
        }
      ];

      gaps = {
        inner.horizontal = 8;
        inner.vertical = 8;
        outer.left = 8;
        outer.bottom = 8;
        outer.top = 8;
        outer.right = 8;
      };

      mode.main.binding = {
        # Focus movement (vim-style)
        alt-h = "focus left";
        alt-j = "focus down";
        alt-k = "focus up";
        alt-l = "focus right";

        # Move windows
        alt-shift-h = "move left";
        alt-shift-j = "move down";
        alt-shift-k = "move up";
        alt-shift-l = "move right";

        # Resize mode — notify sketchybar of mode change
        alt-r = [
          "mode resize"
          "exec-and-forget /run/current-system/sw/bin/sketchybar --trigger aerospace_mode_change MODE=resize"
        ];

        # Join windows into sub-container (replaces i3-style split)
        alt-v = "join-with right";
        alt-b = "join-with down";

        # Layout toggles
        alt-comma = "layout tiles horizontal vertical";
        alt-period = "layout accordion horizontal vertical";

        # Fullscreen
        alt-f = "fullscreen";

        # Float toggle
        alt-shift-space = "layout floating tiling";

        # Close focused window
        alt-shift-q = "close";

        alt-tab = "workspace-back-and-forth";

        # Workspace switching
        alt-1 = "workspace 1";
        alt-2 = "workspace 2";
        alt-3 = "workspace 3";
        alt-4 = "workspace 4";
        alt-5 = "workspace 5";
        alt-6 = "workspace 6";
        alt-7 = "workspace 7";
        alt-8 = "workspace 8";
        alt-9 = "workspace 9";

        # Move window to workspace
        alt-shift-1 = "move-node-to-workspace 1";
        alt-shift-2 = "move-node-to-workspace 2";
        alt-shift-3 = "move-node-to-workspace 3";
        alt-shift-4 = "move-node-to-workspace 4";
        alt-shift-5 = "move-node-to-workspace 5";
        alt-shift-6 = "move-node-to-workspace 6";
        alt-shift-7 = "move-node-to-workspace 7";
        alt-shift-8 = "move-node-to-workspace 8";
        alt-shift-9 = "move-node-to-workspace 9";
      };

      mode.resize.binding = {
        h = "resize width -50";
        j = "resize height +50";
        k = "resize height -50";
        l = "resize width +50";
        # Return to main — notify sketchybar to hide the mode indicator
        enter = [
          "mode main"
          "exec-and-forget /run/current-system/sw/bin/sketchybar --trigger aerospace_mode_change MODE=main"
        ];
        esc = [
          "mode main"
          "exec-and-forget /run/current-system/sw/bin/sketchybar --trigger aerospace_mode_change MODE=main"
        ];
      };
    };
  };
}
