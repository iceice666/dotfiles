{
  config,
  lib,
  pkgs,
  dotfiles,
  themegenHost,
  desktopWallpaper,
  ...
}:

let
  cfg = config.themegen;

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

  mkThemegenCache =
    name: wallpaper:
    pkgs.runCommand "themegen-cache-${name}"
      {
        nativeBuildInputs = [ pkgs.themegen ];
        passthru.targets = renderTargetNames;
        preferLocalBuild = true;
      }
      ''
        runHook preBuild

        mkdir -p "$out"

        themegen render \
          --image ${lib.escapeShellArg "${wallpaper}"} \
          --scheme tonal-spot \
          --material-contrast 0.0 \
          --base16-contrast 0.3 \
          --base16-mode follow-palette \
          ${renderArgs}

        runHook postBuild
      '';

  themegenCache = mkThemegenCache themegenHost desktopWallpaper;

  # Wallpaper ids come from file names and become store names and state keys.
  wallpaperId =
    wallpaper:
    let
      fileName = builtins.baseNameOf (toString wallpaper);
      stem = builtins.match "(.+)\\.[^.]+" fileName;
      id = if stem == null then fileName else builtins.head stem;
    in
    if builtins.match "[A-Za-z0-9_-]+" id != null then
      id
    else
      throw "themegen: wallpaper id '${id}' must match [A-Za-z0-9_-]+";

  themegenWallpapers = map (
    wallpaper:
    let
      id = wallpaperId wallpaper;
    in
    {
      inherit id wallpaper;
      cache = mkThemegenCache "${themegenHost}-${id}" wallpaper;
    }
  ) cfg.wallpapers;

  wallpaperIds = map (entry: entry.id) themegenWallpapers;

  dynamic = cfg.wallpapers != [ ];
  themegenStateDir = "${config.xdg.stateHome}/themegen";

  # Dynamic hosts link through the mutable state directory so a runtime
  # switcher can swap the rendered set without a Home Manager generation.
  homeFiles = builtins.listToAttrs (
    map (target: {
      name = target;
      value.source =
        if dynamic then
          config.lib.file.mkOutOfStoreSymlink "${themegenStateDir}/current/${target}"
        else
          "${themegenCache}/${target}";
    }) renderTargetNames
  );
in
{
  options.themegen.wallpapers = lib.mkOption {
    type = lib.types.listOf lib.types.path;
    default = [ ];
    description = ''
      Wallpaper set for runtime rotation. When non-empty, a theme cache is
      rendered for every wallpaper and rendered files link to
      `$XDG_STATE_HOME/themegen/current`, which a host switcher must populate.
    '';
  };

  config = {
    assertions = [
      {
        assertion = lib.unique wallpaperIds == wallpaperIds;
        message = "themegen.wallpapers must have unique file names: ${toString wallpaperIds}";
      }
    ];

    _module.args = {
      inherit themegenCache themegenStateDir themegenWallpapers;
      themegenTargets = renderTargetNames;
    };

    home.packages = [ pkgs.themegen ];

    home.file = homeFiles;
  };
}
