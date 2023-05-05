# IME Support
export GTK_IM_MODULE=fcitx
export QT_IN_MODULE=fcitx
export XMODIFIRES=@im=fcitx
export SDL_IM_MODULE=fcitx
export GLFW_IM_MODULE=fcitx

# resolution
setxkbmap -option caps:swapescape

# swap caps and esc
xrandr --output Virtual1 --mode 2560x1440

export DWM=~/dwm 
exec dwm
