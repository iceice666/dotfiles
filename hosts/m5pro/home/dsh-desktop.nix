{
  config,
  dotfiles,
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

  # Declared identically in pi.nix; sops-nix merges equal definitions.
  sops.secrets.exa_api_key = {
    sopsFile = dotfiles + /sensitive/shared/exa.yaml;
    mode = "0400";
  };
  sops.templates."dsh-desktop-env" = {
    path = "${config.programs.dsh-desktop.dshHome}/.env";
    mode = "0600";
    content = ''
      EXA_API_KEY=${config.sops.placeholder.exa_api_key}
    '';
  };
}
