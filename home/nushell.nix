{...}: {
  programs.nushell = {
    enable = true;
    configFile.source = ../config/nu/config.nu;
    envFile.source = ../config/nu/env.nu;
    extraConfig = "source ${../config/nu/custom.nu}";
  };
}
