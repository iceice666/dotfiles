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
    (dotfiles + /common/configuration)
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
    };
    taps = [
      "pear-devs/pear"
    ];
    brews = [ ];
    casks = [
      "termius" # nixpkgs has Linux-only build
      "android-commandlinetools" # sdkmanager, avdmanager, etc.
      "android-ndk" # NDK (installs to /usr/local/share/android-ndk or Homebrew prefix)
      "stats"
      "snipaste"
      "karabiner-elements"
      "obs" # OBS Studio (not available in nixpkgs for aarch64-darwin)
      "pear-devs/pear/pear-desktop"
      "zen"
      "pearcleaner"
    ];
  };

  nixpkgs.config.allowUnfree = true;

  # macOS-only system packages (desktop apps, macOS-specific tools)
  environment.systemPackages = with pkgs; [
    orbstack
    ghostty-bin
  ];

  # Necessary for using flakes on this system.
  nix.settings.experimental-features = "nix-command flakes";
  nix.settings.trusted-users = [
    "root"
    username
  ];

  # Enable alternative shell support in nix-darwin.
  programs.fish.enable = true;

  users.users.${username} = {
    name = username;
    home = homeDirectory;
    shell = pkgs.fish;
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {
      inherit
        inputs
        self
        username
        homeDirectory
        dotfiles
        unstablePkgs
        ;
    };
    users.${username} = {
      imports = [ ../home ];
    };
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
