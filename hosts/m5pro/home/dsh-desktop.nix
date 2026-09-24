{
  config,
  inputs,
  ...
}:

{
  imports = [ inputs.dsh-desktop.homeManagerModules.default ];

  # DeepSeek Harness desktop app, copied to ~/Applications/Home Manager Apps.
  # Name and icon are baked into the bundle; set them here, not in the app.
  programs.dsh-desktop = {
    enable = true;
    name = "大燒貨";
    icon = ../../../assets/dsh.png;
  };

  # The app keeps its own DSH home instead of ~/.dsh, so it needs its own copy
  # of the home-layer .env that dsh.nix renders for the CLI.
  sops.templates."dsh-desktop-env" = {
    path = "${config.programs.dsh-desktop.dshHome}/.env";
    mode = "0600";
    inherit (config.sops.templates."dsh-env") content;
  };
}
