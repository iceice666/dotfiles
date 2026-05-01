{
  pkgs,
  lib,
  dotfiles,
  desktopWallpaper,
  ...
}:

let
  templateDir = dotfiles + /common/home/themegen/templates;
  templateModules = map (name: import (templateDir + "/${name}") { inherit lib pkgs; }) (
    builtins.attrNames (
      lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "lib.nix") (
        builtins.readDir templateDir
      )
    )
  );

  generatedEntries = lib.concatMap (module: module.generated or [ ]) templateModules;
  homeFileEntries = lib.concatMap (module: module.homeFiles or [ ]) templateModules;

  hostPlatform =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "darwin"
    else if pkgs.stdenv.hostPlatform.isLinux then
      "linux"
    else
      pkgs.stdenv.hostPlatform.system;

  supportsPlatform = entry: entry.platforms == [ ] || builtins.elem hostPlatform entry.platforms;

  renderArgs = lib.concatMapStringsSep " " (
    entry: "--render \"${entry.template}=$out/${entry.output}\""
  ) (lib.filter (entry: entry.type == "render") generatedEntries);

  copyCommands = lib.concatMapStringsSep "\n" (entry: ''
    install -Dm644 "${entry.source}" "$out/${entry.output}"
  '') (lib.filter (entry: entry.type == "copy") generatedEntries);

  generated =
    pkgs.runCommandLocal "themegen-themes"
      {
        nativeBuildInputs = [ pkgs.themegen ];
      }
      ''
        themegen render \
          --image "${desktopWallpaper}" \
          --scheme tonal-spot \
          --base16-contrast 0.3 \
          --base16-mode follow-palette \
          ${renderArgs}

        ${copyCommands}
      '';

  homeFiles = builtins.listToAttrs (
    map (entry: {
      name = entry.target;
      value.source = "${generated}/${entry.source}";
    }) (lib.filter supportsPlatform homeFileEntries)
  );
in
{
  home.packages = [ pkgs.themegen ];

  home.file = homeFiles;

  programs.opencode.settings.theme = "themegen";
}
