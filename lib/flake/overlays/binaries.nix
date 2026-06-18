{ dotfiles, inputs }:

final: prev: {
  appearance-scheduler = final.callPackage (dotfiles + /pkgs/appearance-scheduler) { };
  blocky-bin = final.callPackage (dotfiles + /pkgs/blocky-bin) { };
  claude-code-bin = final.callPackage (dotfiles + /pkgs/claude-code-bin) { };
  cliproxyapi-bin = final.callPackage (dotfiles + /pkgs/cliproxyapi-bin) { };
  codex-cli-bin = final.callPackage (dotfiles + /pkgs/codex-cli-bin) { };
  default-browser = final.callPackage (dotfiles + /pkgs/default-browser) { };
  equibop-bin = final.callPackage (dotfiles + /pkgs/equibop-bin) { };
  framework-eww-state = final.callPackage (dotfiles + /pkgs/framework-eww-state) { };
  ketch = final.callPackage (dotfiles + /pkgs/ketch) { };
  pi-coding-agent-bin = final.callPackage (dotfiles + /pkgs/pi-coding-agent-bin) { };
  rime-frost = final.callPackage (dotfiles + /pkgs/rime-frost) { };
  rime-octagram-zh-hant-essay-bgw = final.callPackage (
    dotfiles + /pkgs/rime-octagram-zh-hant-essay-bgw
  ) { };
  themegen = final.callPackage (dotfiles + /pkgs/themegen) { };
  utiluti = final.callPackage (dotfiles + /pkgs/utiluti) { };
  zed-bin = final.callPackage (dotfiles + /pkgs/zed-bin) { };
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
}
