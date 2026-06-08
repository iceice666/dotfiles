{
  inputs,
  nixpkgs-unstable,
  dotfiles,
}:

final: prev: {
  inherit (prev.lixPackageSets.stable)
    nix-eval-jobs
    nix-fast-build
    nixpkgs-review
    ;

  claude-code-bin = final.callPackage (dotfiles + /pkgs/claude-code-bin) { };
  codex-cli-bin = final.callPackage (dotfiles + /pkgs/codex-cli-bin) { };
  default-browser = final.callPackage (dotfiles + /pkgs/default-browser) { };
  equibop-bin = final.callPackage (dotfiles + /pkgs/equibop-bin) { };
  framework-eww-state = final.callPackage (dotfiles + /pkgs/framework-eww-state) { };
  ketch = final.callPackage (dotfiles + /pkgs/ketch) { };
  kaguya-bin =
    if final.stdenv.hostPlatform.isLinux then
      inputs."kaguya-browser".packages.${final.stdenv.hostPlatform.system}.default
    else
      throw "kaguya-bin is only supported on Linux";
  niri-scratchpad-helper =
    if final.stdenv.hostPlatform.isLinux then
      final.callPackage (inputs."niri-scratchpad-helper" + /src/drv.nix) { }
    else
      throw "niri-scratchpad-helper is only supported on Linux";
  reimu-on-starlit-water =
    if final.stdenv.hostPlatform.isLinux then
      let
        unstablePkgs = import nixpkgs-unstable {
          system = final.stdenv.hostPlatform.system;
          config = {
            allowUnfree = true;
            cudaSupport = true;
          };
        };
      in
      final.callPackage (inputs."reimu-on-starlit-water" + /nix/package.nix) {
        rustPlatform = final.makeRustPlatform {
          inherit (unstablePkgs) cargo rustc;
        };
      }
    else
      throw "reimu-on-starlit-water is only supported on Linux";
  rime-frost = final.callPackage (dotfiles + /pkgs/rime-frost) { };
  rime-octagram-zh-hant-essay-bgw = final.callPackage (
    dotfiles + /pkgs/rime-octagram-zh-hant-essay-bgw
  ) { };
  zen-bin =
    if final.stdenv.hostPlatform.isLinux then
      final.wrapFirefox
        (inputs."zen-browser".packages.${final.stdenv.hostPlatform.system}.zen-browser-unwrapped
          or inputs."zen-browser".packages.${final.stdenv.hostPlatform.system}.default
        )
        {
          pname = "zen-bin";
          applicationName = "zen";
        }
    else
      final.callPackage (dotfiles + /pkgs/zen-bin) { };
  themegen = final.callPackage (dotfiles + /pkgs/themegen) { };
  pi-coding-agent-bin = final.callPackage (dotfiles + /pkgs/pi-coding-agent-bin) { };
  utiluti = final.callPackage (dotfiles + /pkgs/utiluti) { };
  zed-bin = final.callPackage (dotfiles + /pkgs/zed-bin) { };
  linux_zen_7_0 = prev.linux_zen.override {
    argsOverride = rec {
      version = "7.0.9";
      suffix = "zen1";
      modDirVersion = final.lib.versions.pad 3 "${version}-${suffix}";
      structuredExtraConfig = builtins.removeAttrs prev.linux_zen.structuredExtraConfig [
        "PREEMPT_VOLUNTARY"
      ];
      src = final.fetchFromGitHub {
        owner = "zen-kernel";
        repo = "zen-kernel";
        rev = "v${version}-${suffix}";
        sha256 = "1fm1v1ghhls6kvfn6mdzcsq8rmng428ws329xb6ry1j3ax3apvmy";
      };
    };
  };
  linuxPackages_zen_7_0 = final.linuxPackagesFor final.linux_zen_7_0;
  eww =
    if final.stdenv.hostPlatform.isLinux then
      prev.eww.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace crates/eww/src/app.rs \
            --replace-fail \
              "    window.set_visual(visual.as_ref());" \
              "    window.set_visual(visual.as_ref());
              window.set_app_paintable(true);"
        '';
      })
    else
      prev.eww;
  direnv = prev.direnv.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      for makefile in Makefile GNUmakefile; do
        if [ -f "$makefile" ]; then
          substituteInPlace "$makefile" --replace "-linkmode=external" ""
        fi
      done
    '';
  });
}
