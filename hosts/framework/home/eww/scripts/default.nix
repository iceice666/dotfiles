{
  ewwConfigDir,
  icons,
  pkgs,
}:
let
  shared = (import ./shared.nix { inherit pkgs; }) // {
    inherit ewwConfigDir icons;
  };
in
(import ./focus-window.nix shared)
// (import ./niri-state.nix shared)
// (import ./media-status.nix shared)
// (import ./perf-status.nix shared)
// (import ./battery-status.nix shared)
// (import ./audio-status.nix shared)
// (import ./datetime-status.nix shared)
// (import ./notifications-status.nix shared)
// (import ./actions.nix (shared // { inherit ewwConfigDir pkgs; }))
