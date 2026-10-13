{
  config,
  lib,
  pkgs,
  modulesPath,
  dotfiles,
  ...
}:

let
  installer = pkgs.writeShellApplication {
    name = "framework-install";
    runtimeInputs = with pkgs; [
      btrfs-progs
      coreutils
      dosfstools
      git
      gnugrep
      parted
      python3
      util-linux
    ];
    text = ''
      export FRAMEWORK_INSTALL_SOURCE=${lib.escapeShellArg (toString dotfiles)}
      export PATH=${
        lib.makeBinPath [
          config.system.build.nixos-install
          pkgs.nixos-enter
        ]
      }:"$PATH"
      ${builtins.readFile (dotfiles + /scripts/framework-install)}
    '';
  };
in
{
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  networking.hostName = "framework-installer";
  boot.zfs.forceImportRoot = false;
  services.openssh.enable = lib.mkForce false;
  time.timeZone = "Asia/Taipei";

  image.baseName = lib.mkForce "framework-installer-${config.system.nixos.release}";
  isoImage = {
    volumeID = "FRAMEWORK_INSTALL";
    appendToMenuLabel = " (Framework reinstall)";
    makeBiosBootable = false;
  };

  environment.systemPackages = [
    installer
    pkgs.just
  ];
  environment.etc = {
    "framework-installer".text = "Full-disk, unencrypted, online Framework installer.\n";
    "framework-dotfiles".source = dotfiles;
    "framework-install-guide.md".source = ./README.md;
  };

  users.motd = lib.mkForce ''
    Framework reinstall ISO — no disks are changed automatically.
    Connect to the internet using nmtui, then run:
      sudo framework-install --disk /dev/disk/by-id/<target> --swap-gib <size>
    Preview without changing disks: add --dry-run.
    WARNING: installation erases the entire selected disk, including /home.
    Guide: /etc/framework-install-guide.md
    Embedded dotfiles: /etc/framework-dotfiles
  '';
}
