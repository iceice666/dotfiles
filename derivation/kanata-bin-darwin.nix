{
  pkgs ? import <nixpkgs> {},
  config,
  lib,
  ...
}:
with lib; let
  KarabinerDriverPath = "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager";

  version = "1.8.0";

  # Package source for kanata-bin
  aarch64-darwin = builtins.fetchurl {
    url = "https://github.com/jtroo/kanata/releases/download/v${version}/kanata_macos_arm64";
    sha256 = "sha256-oHIpb1Hvi3gJUYnYJWXGs1QPoHerdWCA1+bHjG4QAQ4=";
  };

  x86_64-darwin = builtins.fetchurl {
    url = "https://github.com/jtroo/kanata/releases/download/v${version}/kanata_macos_x86_64";
    sha256 = "sha256-5p7KR0TWmCnDjKR0r2zT7q6Au8S6iNr5xgtitqBBwZ8=";
  };

  # Package definition for kanata-bin
  kanata-pkg = pkgs.stdenvNoCC.mkDerivation {
    pname = "kanata-bin";
    inherit version;

    src =
      if pkgs.stdenvNoCC.hostPlatform.system == "x86_64-darwin"
      then x86_64-darwin
      else aarch64-darwin;

    phases = ["installPhase"];

    sourceRoot = ".";

    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/kanata
      chmod +x $out/bin/kanata

      runHook postInstall
    '';

    postInstall = ''
      if [ ! -f ${KarabinerDriverPath} ]; then
        echo ""
        echo "Warning: Karabiner VirtualHIDDevice is not installed!"
        echo "Please install and activate it to use kanata."
        echo "Check https://github.com/jtroo/kanata/releases/tag/v${version} for more information."
        echo ""
      fi
    '';

    meta = {
      platforms = ["aarch64-darwin" "x86_64-darwin"];
      badPlatforms = ["x86_64-linux" "aarch64-linux"];
    };
  };
in {
  options.programs.kanata-bin-darwin = {
    enable = mkOption {
      default = false;
      description = "Enable kanata-bin";
    };

    package = mkOption {
      default = kanata-pkg;
      type = types.package;
      description = "kanata-bin package to use";
    };

    setupLaunchd = mkOption {
      default = false;
      type = types.bool;
      description = "Setup launchd agent for kanata";
    };

    configFile = {
      text = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = ''
          Text of the kanata config file.
          If unset then the source option will be preferred.
        '';
      };

      source = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path of the kanata config file to use.
          If the text option is set, it will be preferred.
        '';
      };
    };
  };
  config = let
    cfg = config.programs.kanata-bin-darwin;
  in
    mkIf cfg.enable {
      environment.systemPackages = [cfg.package];

      # path is /etc/kanata/kanata.kbd
      environment.etc."kanata/kanata.kbd".text =
        if cfg.configFile.text != null
        then cfg.configFile.text
        else if cfg.configFile.source != null
        then builtins.readFile cfg.configFile.source
        else "";

      launchd.agents.kanata = mkIf cfg.setupLaunchd {
        serviceConfig = {
          Label = "kanata";
          RunAtLoad = true;
          KeepAlive = true;
          UserName = "root";
          Program = "/run/current-system/sw/bin/kanata";
          ProgramArguments = [
            "-c"
            "/etc/kanata/kanata.kbd"
          ];
        };
      };
    };
}
