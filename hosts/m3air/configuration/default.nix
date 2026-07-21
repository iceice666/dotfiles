{
  config,
  pkgs,
  inputs,
  self,
  username,
  homeDirectory,
  dotfiles,
  unstablePkgs,
  ...
}:

let
  homebrewTrustFile = pkgs.writeText "homebrew-trust.json" (
    builtins.toJSON {
      trustedtaps = [ "pear-devs/pear" ];
    }
  );
  homebrewBrewfile = pkgs.writeText "Brewfile" config.homebrew.brewfile;
in
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
      cleanup = "none";
    };
    taps = [
      "pear-devs/pear"
    ];
    brews = [
      "odin"
      "ols"
      "odinfmt"
    ];
    casks = [
      "termius" # nixpkgs has Linux-only build
      "android-studio"
      "android-commandlinetools" # sdkmanager, avdmanager, etc.
      "android-ndk" # NDK (installs to /usr/local/share/android-ndk or Homebrew prefix)
      "stats"
      "snipaste"
      "karabiner-elements"
      "obs" # OBS Studio (not available in nixpkgs for aarch64-darwin)
      "squirrel-app" # Rime frontend for macOS
      "pear-devs/pear/pear-desktop"
      "helium-browser"
      "ungoogled-chromium"
      "pearcleaner"
      "mos" # per-device scroll direction (reverse mouse, keep trackpad natural)
    ];
  };

  system.activationScripts = {
    preActivation.text = ''
      trust_dir="${homeDirectory}/.homebrew"
      ${pkgs.coreutils}/bin/install -d -m 0700 -o ${username} -g staff "$trust_dir"
      ${pkgs.coreutils}/bin/install -m 0600 -o ${username} -g staff ${homebrewTrustFile} "$trust_dir/trust.json"
    '';

    postActivation.text = ''
      if [ -x /opt/homebrew/bin/brew ]; then
        PATH="/opt/homebrew/bin:${pkgs.mas}/bin:$PATH" \
          /usr/bin/sudo \
            --preserve-env=PATH \
            --user=${username} \
            --set-home \
            ${pkgs.coreutils}/bin/env HOMEBREW_NO_AUTO_UPDATE=1 \
            /opt/homebrew/bin/brew bundle cleanup \
              --file=${homebrewBrewfile} \
              --force \
              --zap
      fi
    '';
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
