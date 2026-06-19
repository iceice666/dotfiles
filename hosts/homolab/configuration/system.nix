{ pkgs, ... }:

{
  nix.settings = {
    substituters = [ "https://cache.nixos-cuda.org" ];
    trusted-public-keys = [ "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=" ];
    # Allow iceice666 to submit remote builds from m3air.
    trusted-users = [ "iceice666" ];
  };

  # oh-my-pi (omp) ships a Bun standalone executable left unpatched (see
  # pkgs/oh-my-pi-bin); it needs nix-ld to provide the generic glibc loader.
  programs.nix-ld.enable = true;

  # Keep aarch64 emulation available for ad-hoc package debugging.
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
    timeout = 10;
  };

  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Kernel surface hardening: keep ESP/RxRPC blocked until the shared-frag
  # fix status is explicit, and block unused Bluetooth and kernel SMB modules.
  boot.blacklistedKernelModules = [
    "esp4"
    "esp6"
    "rxrpc"
    "ksmbd"
    "bluetooth"
    "btusb"
    "btrtl"
    "btintel"
    "btbcm"
    "btmtk"
  ];
  boot.extraModprobeConfig = ''
    install esp4 /run/current-system/sw/bin/false
    install esp6 /run/current-system/sw/bin/false
    install rxrpc /run/current-system/sw/bin/false
    install ksmbd /run/current-system/sw/bin/false
    install bluetooth /run/current-system/sw/bin/false
    install btusb /run/current-system/sw/bin/false
    install btrtl /run/current-system/sw/bin/false
    install btintel /run/current-system/sw/bin/false
    install btbcm /run/current-system/sw/bin/false
    install btmtk /run/current-system/sw/bin/false
  '';
  system.activationScripts.kernelSurfaceMitigation.text = ''
    for module in esp4 esp6 rxrpc ksmbd bluetooth btusb btrtl btintel btbcm btmtk; do
      ${pkgs.kmod}/bin/rmmod "$module" 2>/dev/null || true
    done
    ${pkgs.coreutils}/bin/sync
    echo 3 > /proc/sys/vm/drop_caches
  '';

  time.timeZone = "Asia/Taipei";
}
