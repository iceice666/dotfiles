{
  lib,
  pkgs,
  ...
}:

let
  rimeDir =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "$HOME/Library/Rime"
    else if pkgs.stdenv.hostPlatform.isLinux then
      "$HOME/.local/share/fcitx5/rime"
    else
      throw "rime: unsupported platform ${pkgs.stdenv.hostPlatform.system}";

  defaultCustom = pkgs.writeText "default.custom.yaml" ''
    patch:
      schema_list:
        - schema: rime_frost
  '';

  rimeFrostCustom = pkgs.writeText "rime_frost.custom.yaml" ''
    patch:
      grammar:
        language: zh-hant-t-essay-bgw
        non_collocation_penalty: -4
        collocation_max_length: 5
        collocation_min_length: 2
        collocation_penalty: -14
      "translator/contextual_suggestions": true
      "translator/enable_user_dict": true
      "translator/max_homophones": 4
      "translator/max_homographs": 2
      "switches/@1/reset": 1
      "traditionalize/opencc_config": s2tw.json
  '';

  rimeDataPkgs = [
    pkgs.rime-frost
    pkgs.rime-octagram-zh-hant-essay-bgw
  ];

  fcitx5Rime = pkgs.fcitx5-rime.override {
    rimeDataPkgs = [ pkgs.rime-data ] ++ rimeDataPkgs;
  };
in
{
  home.packages = [
    pkgs.opencc
  ];

  home.activation.rimeFrost = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    rime_dir="${rimeDir}"

    mkdir -p "$rime_dir"

    ${lib.concatMapStringsSep "\n" (pkg: ''
      ${pkgs.rsync}/bin/rsync -a --chmod=Du+rwx,Fu+rw "${pkg}/share/rime-data/" "$rime_dir/"
    '') rimeDataPkgs}

    install -m 0644 ${defaultCustom} "$rime_dir/default.custom.yaml"
    install -m 0644 ${rimeFrostCustom} "$rime_dir/rime_frost.custom.yaml"
  '';

  i18n.inputMethod = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
    enable = true;
    type = "fcitx5";

    fcitx5 = {
      waylandFrontend = true;
      addons = [
        fcitx5Rime
        pkgs.fcitx5-gtk
      ];
      settings.inputMethod = {
        GroupOrder."0" = "Default";
        "Groups/0" = {
          Name = "Default";
          "Default Layout" = "us";
          DefaultIM = "rime";
        };
        "Groups/0/Items/0".Name = "keyboard-us";
        "Groups/0/Items/1".Name = "rime";
      };
    };
  };
}
