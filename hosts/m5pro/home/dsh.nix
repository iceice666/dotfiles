{ config, dotfiles, ... }:

{
  # Declared identically in omp.nix / pi.nix; sops-nix merges equal definitions.
  sops.secrets.exa_api_key = {
    sopsFile = dotfiles + /sensitive/shared/exa.yaml;
    mode = "0400";
  };

  # dsh loads its home-layer ~/.dsh/.env at boot; @deepseek-ai/dsh-web-search-exa
  # falls back to EXA_API_KEY from that launch environment.
  sops.templates."dsh-env".path = "${config.home.homeDirectory}/.dsh/.env";
  sops.templates."dsh-env".mode = "0600";
  sops.templates."dsh-env".content = ''
    EXA_API_KEY=${config.sops.placeholder.exa_api_key}
  '';
}
