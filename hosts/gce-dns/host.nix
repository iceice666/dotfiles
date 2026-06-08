{
  inputs,
  dotfiles,
  name,
}:

{
  inherit name;
  kind = "nixos";
  system = "x86_64-linux";
  username = "iceice666";
  homeDirectory = "/home/iceice666";

  modules = [
    "${inputs.nixpkgs}/nixos/modules/virtualisation/google-compute-image.nix"
    ./configuration
  ];

  features = {
    homeManager = false;
    sops = false;
  };

  deploy = {
    enable = true;
    hostname = name;
    sshUser = "iceice666";
    remoteBuild = true;
  };
}
