{ username, ... }:

{
  services.xserver = {
    enable = true;
    windowManager.bspwm.enable = true;
    windowManager.bspwm.sxhkd.configFile = "/home/${username}/.config/sxhkd/sxhkdrc";
    displayManager.lightdm.enable = true;
  };

  services.displayManager.defaultSession = "none+bspwm";
}
