{ pkgs, inputs, self, username, homeDirectory, ... }:

{
  imports = [ ./system-defaults.nix ];

  system.primaryUser = username;

  # Homebrew (only packages unavailable or unsupported on macOS in nixpkgs)
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
    };
    brews = [];
    casks = [
      "helium-browser" # not in nixpkgs
      "termius"        # nixpkgs has Linux-only build
    ];
  };

  nixpkgs.config.allowUnfree = true;

  # macOS-only system packages (desktop apps, macOS-specific tools)
  environment.systemPackages = with pkgs; [
    orbstack
    ghostty-bin
    cloudflare-warp
  ];

  # Necessary for using flakes on this system.
  nix.settings.experimental-features = "nix-command flakes";

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
    extraSpecialArgs = { inherit inputs self username homeDirectory; };
    users.${username} = { imports = [ ../home ]; };
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
