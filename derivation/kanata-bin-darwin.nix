{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  version = "1.7.0";

  # Package source for kanata-bin
  aarch64-darwin = builtins.fetchurl {
    url = "https://github.com/jtroo/kanata/releases/download/v${version}/kanata_macos_arm64";
    sha256 = "sha256-g62A+6+Mew7A4XBSoCygswV8u+r4oCOmFUHxUUqTa0M=";
  };

  x86_64-darwin = builtins.fetchurl {
    url = "https://github.com/jtroo/kanata/releases/download/v${version}/kanata_macos_x86_64";
    sha256 = "sha256-4/DZnlEqhMXK4fY+ccB+zb/2bcibBTq6CrtPne4MrcA=";
  };

  # Package definition for kanata-bin
  kanata-pkg = pkgs.stdenv.mkDerivation {
    pname = "kanata-bin";
    inherit version;

    src =
      if pkgs.stdenv.hostPlatform.system == "x86_64-darwin"
      then x86_64-darwin
      else aarch64-darwin;

    phases = ["installPhase"];

    sourceRoot = ".";

    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/kanata
      chmod +x $out/bin/kanata
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
    cfgDir = "Library/Application Support/kanata";
  in
    mkIf cfg.enable {
      home.packages = [cfg.package];
      home.file."${cfgDir}/kanata.kbd".text =
        if cfg.configFile.text != null
        then cfg.configFile.text
        else if cfg.configFile.source != null
        then builtins.readFile cfg.configFile.source
        else "";
    };
}
