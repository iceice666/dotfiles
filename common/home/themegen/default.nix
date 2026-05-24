{
  lib,
  pkgs,
  dotfiles,
  themegenHost,
  desktopWallpaper,
  ...
}:

let
  listFiles =
    dir: prefix:
    let
      entries = builtins.readDir dir;
    in
    lib.concatMap (
      name:
      let
        path = dir + "/${name}";
        type = entries.${name};
        target = if prefix == "" then name else "${prefix}/${name}";
      in
      if type == "directory" then listFiles path target else lib.optional (type == "regular") target
    ) (builtins.attrNames entries);

  renderTargetsFor =
    dir:
    if builtins.pathExists dir then
      builtins.listToAttrs (
        map (target: {
          name = target;
          value = dir + "/${target}";
        }) (listFiles dir "")
      )
    else
      { };

  renderTargets =
    renderTargetsFor (dotfiles + /themegen/common)
    // renderTargetsFor (dotfiles + "/themegen/${themegenHost}");
  renderTargetNames = builtins.attrNames renderTargets;

  renderArgs = lib.concatStringsSep " \\\n    " (
    lib.mapAttrsToList (
      target: template:
      ''--render ${lib.escapeShellArg "${template}"}="$out"/${lib.escapeShellArg target}''
    ) renderTargets
  );

  themegenCache =
    pkgs.runCommand "themegen-cache-${themegenHost}"
      {
        nativeBuildInputs = [ pkgs.themegen ];
        passthru.targets = renderTargetNames;
        preferLocalBuild = true;
      }
      ''
        runHook preBuild

        mkdir -p "$out"

        themegen render \
          --image ${lib.escapeShellArg "${desktopWallpaper}"} \
          --scheme tonal-spot \
          --material-contrast 0.0 \
          --base16-contrast 0.3 \
          --base16-mode follow-palette \
          ${renderArgs}

        runHook postBuild
      '';

  homeFiles = builtins.listToAttrs (
    map (target: {
      name = target;
      value.source = "${themegenCache}/${target}";
    }) renderTargetNames
  );
in
{
  _module.args = {
    inherit themegenCache;
  };

  home.packages = [ pkgs.themegen ];

  home.file = homeFiles;
}
