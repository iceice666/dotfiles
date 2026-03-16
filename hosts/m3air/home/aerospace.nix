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
      config-version = 2;

      enable-normalization-flatten-containers = true;
      enable-normalization-opposite-orientation-for-nested-containers = true;
      automatically-unhide-macos-hidden-apps = true;

      after-startup-command = [
        # JankyBorders has a built-in detection of already running process,
        # so it won't be run twice on AeroSpace restart
        "exec-and-forget /run/current-system/sw/bin/borders active_color=0xffe1e3e4 inactive_color=0xff494d64 width=5.0"
        "exec-and-forget /etc/profiles/per-user/iceice666/bin/aerospace-swipe"
        "exec-and-forget /etc/profiles/per-user/iceice666/bin/mybar"
        # "exec-and-forget /etc/profiles/per-user/iceice666/bin/sketchybar"
      ];

      exec-on-workspace-change = [
        "/bin/bash"
        "-c"
        "printf \"FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE\\n\" | nc -U /tmp/mybar-wm-bridge.sock "
      ];

      on-mode-changed = [
      ];
      on-focused-monitor-changed = [
        "move-mouse monitor-lazy-center"
        "exec-and-forget printf \"UPDATE_ALL\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
      ];
      on-window-detected = [
        {
          "if".app-id = "com.mitchellh.ghostty";
          run = [ "layout tiling" ];
        }
        {
          "if" = {
            app-id = "app.zen-browser.zen";
            window-title-regex-substring = "Extension:|登入";
          };
          run = [ "layout floating" ];
        }
	{
	  "if" = {
	    app-id = "org.equicord.equibop";
	    window-title-regex-substring = "Equicord QuickCSS Editor|Developer Tools";
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

      persistent-workspaces = [ ];

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

        # Resize (quick)
        alt-minus = "resize smart -50";
        alt-equal = "resize smart +50";

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
        alt-shift-tab = "move-workspace-to-monitor --wrap-around next";

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

	alt-leftSquareBracket = "workspace prev";
	alt-rightSquareBracket = "workspace next";

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

        # Mode switches
        alt-r = [
          "mode resize"
          "exec-and-forget printf \"MODE=resize\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
        ];
        alt-m = [
          "mode monitor"
          "exec-and-forget printf \"MODE=monitor\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
        ];
        alt-shift-semicolon = [
          "mode service"
          "exec-and-forget printf \"MODE=service\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
        ];
      };

      # Resize mode
      mode.resize.binding = {
        h = "resize width -50";
        j = "resize height +50";
        k = "resize height -50";
        l = "resize width +50";
        enter = [
          "mode main"
          "exec-and-forget printf \"MODE=main\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
        ];
        esc = [
          "mode main"
          "exec-and-forget printf \"MODE=main\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
        ];
      };

      # Monitor mode — focus/move across monitors
      mode.monitor.binding = {
        h = [
          "focus-monitor left"
          "mode main"
          "exec-and-forget printf \"MODE=main\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
        ];
        j = [
          "focus-monitor down"
          "mode main"
          "exec-and-forget printf \"MODE=main\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
        ];
        k = [
          "focus-monitor up"
          "mode main"
          "exec-and-forget printf \"MODE=main\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
        ];
        l = [
          "focus-monitor right"
          "mode main"
          "exec-and-forget printf \"MODE=main\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
        ];
        shift-h = [
          "move-node-to-monitor left"
          "mode main"
          "exec-and-forget printf \"MODE=main\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
        ];
        shift-j = [
          "move-node-to-monitor down"
          "mode main"
          "exec-and-forget printf \"MODE=main\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
        ];
        shift-k = [
          "move-node-to-monitor up"
          "mode main"
          "exec-and-forget printf \"MODE=main\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
        ];
        shift-l = [
          "move-node-to-monitor right"
          "mode main"
          "exec-and-forget printf \"MODE=main\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
        ];
        enter = [
          "mode main"
          "exec-and-forget printf \"MODE=main\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
        ];
        esc = [
          "mode main"
          "exec-and-forget printf \"MODE=main\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
        ];
      };

      # Service mode — maintenance & join-with
      mode.service.binding = {
        # Managed by Nix
        # esc = [
        #   "reload-config"
        #   "mode main"
        #   "exec-and-forget printf \"MODE=main\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
        # ];
        r = [
          "flatten-workspace-tree"
          "mode main"
          "exec-and-forget printf \"MODE=main\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
        ];
        f = [
          "layout floating tiling"
          "mode main"
          "exec-and-forget printf \"MODE=main\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
        ];
        backspace = [
          "close-all-windows-but-current"
          "mode main"
          "exec-and-forget printf \"MODE=main\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
        ];

        # Join-with (all 4 directions)
        alt-shift-h = [
          "join-with left"
          "mode main"
          "exec-and-forget printf \"MODE=main\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
        ];
        alt-shift-j = [
          "join-with down"
          "mode main"
          "exec-and-forget printf \"MODE=main\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
        ];
        alt-shift-k = [
          "join-with up"
          "mode main"
          "exec-and-forget printf \"MODE=main\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
        ];
        alt-shift-l = [
          "join-with right"
          "mode main"
          "exec-and-forget printf \"MODE=main\\n\" | nc -U /tmp/mybar-wm-bridge.sock"
        ];
      };
    };
  };
}
