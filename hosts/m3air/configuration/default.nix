{
  pkgs,
  inputs,
  self,
  username,
  homeDirectory,
  dotfiles,
  unstablePkgs,
  ...
}:

{
  imports = [
    ./system-defaults.nix
  ];

  sops = {
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "${homeDirectory}/.ssh/id_ed25519" ];
  };

  system.primaryUser = username;

  # Homebrew (only packages unavailable or unsupported on macOS in nixpkgs)
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
      extraFlags = [ "--force-cleanup" ];
    };
    taps = [
      "pear-devs/pear"
    ];
    brews = [ ];
    casks = [
      "termius" # nixpkgs has Linux-only build
      "android-studio"
      "android-commandlinetools" # sdkmanager, avdmanager, etc.
      "android-ndk" # NDK (installs to /usr/local/share/android-ndk or Homebrew prefix)
      "stats"
      "codex"
      "snipaste"
      "karabiner-elements"
      "obs" # OBS Studio (not available in nixpkgs for aarch64-darwin)
      "squirrel-app" # Rime frontend for macOS
      "pear-devs/pear/pear-desktop"
      "zen"
      "ungoogled-chromium"
      "pearcleaner"
      "mos" # per-device scroll direction (reverse mouse, keep trackpad natural)
    ];
  };

  # macOS-only system packages (desktop apps, macOS-specific tools)
  environment.systemPackages = with pkgs; [
    orbstack
    ghostty-bin
  ];

  nix.settings.trusted-users = [
    "root"
    username
  ];

  services.tailscale.enable = true;

  users.users.${username} = {
    name = username;
    home = homeDirectory;
    shell = pkgs.fish;
  };

  networking.computerName = "M3Air";
  networking.hostName = "M3Air";

  # Set Git commit hash for darwin-version.
  system.configurationRevision = self.rev or self.dirtyRev or null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 6;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";
}
