{ lib, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "thunderbolt"
    "usb_storage"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_ROOT";
    fsType = "btrfs";
    options = [
      "subvol=@"
      "compress=zstd"
      "noatime"
      "ssd"
      "space_cache=v2"
    ];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-label/NIXOS_ROOT";
    fsType = "btrfs";
    options = [
      "subvol=@home"
      "compress=zstd"
      "noatime"
      "ssd"
      "space_cache=v2"
    ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-label/NIXOS_ROOT";
    fsType = "btrfs";
    options = [
      "subvol=@nix"
      "compress=zstd"
      "noatime"
      "ssd"
      "space_cache=v2"
    ];
  };

  fileSystems."/var/log" = {
    device = "/dev/disk/by-label/NIXOS_ROOT";
    fsType = "btrfs";
    options = [
      "subvol=@log"
      "compress=zstd"
      "noatime"
      "ssd"
      "space_cache=v2"
    ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/26D2-8AF4";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  swapDevices = [ { device = "/dev/disk/by-label/NIXOS_SWAP"; } ];

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
