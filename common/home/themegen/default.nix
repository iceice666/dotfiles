{
  pkgs,
  lib,
  themegenCache,
  ...
}:

let
  listFiles =
    dir: prefix:
    lib.concatMap (
      name:
      let
        path = dir + "/${name}";
        type = (builtins.readDir dir).${name};
        target = if prefix == "" then name else "${prefix}/${name}";
      in
      if type == "directory" then listFiles path target else lib.optional (type == "regular") target
    ) (builtins.attrNames (builtins.readDir dir));

  homeFiles = builtins.listToAttrs (
    map (target: {
      name = target;
      value.source = "${themegenCache}/${target}";
    }) (listFiles themegenCache "")
  );
in
{
  home.packages = [ pkgs.themegen ];

  home.file = homeFiles;
}
