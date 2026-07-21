{ dotfiles }:

final: prev: {
  appearance-scheduler = final.callPackage (dotfiles + /pkgs/appearance-scheduler) { };
  blocky-bin = final.callPackage (dotfiles + /pkgs/blocky-bin) { };
  claude-code-bin = final.callPackage (dotfiles + /pkgs/claude-code-bin) { };
  cliproxyapi-bin = final.callPackage (dotfiles + /pkgs/cliproxyapi-bin) { };
  default-browser = final.callPackage (dotfiles + /pkgs/default-browser) { };
  equibop-bin = final.callPackage (dotfiles + /pkgs/equibop-bin) { };
  framework-eww-state = final.callPackage (dotfiles + /pkgs/framework-eww-state) { };
  helium-bin = final.callPackage (dotfiles + /pkgs/helium-bin) { };
  oh-my-pi-bin = final.callPackage (dotfiles + /pkgs/oh-my-pi-bin) { };
  rime-frost = final.callPackage (dotfiles + /pkgs/rime-frost) { };
  rime-octagram-zh-hant-essay-bgw = final.callPackage (
    dotfiles + /pkgs/rime-octagram-zh-hant-essay-bgw
  ) { };
  themegen = final.callPackage (dotfiles + /pkgs/themegen) { };
  utiluti = final.callPackage (dotfiles + /pkgs/utiluti) { };
  zed-bin = final.callPackage (dotfiles + /pkgs/zed-bin) { };
}
