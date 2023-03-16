
if [ `id -u` -ne 0 ]; then
   echo "Run this script as root!"
   exit 1
fi

cd ~
git submodule update --remote 

# git
pacman -S git lazygit

# zsh + zplug
pacman -S zsh exa
chsh -s $(which zsh)
curl -sL --proto-redir -all,https \
  https://raw.githubusercontent.com/zplug/installer/master/installer.zsh | zsh

# yay
pacman -S --needed git base-devel
mkdir ~/build
cd ~/build
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si

# hyprland
yay -S hyprland hyprpaper-git xdg-desktop-portal-hyprland-git
pacman -S kitty fuzzel firefox

# fcitx5 & rime
pacman fcitx5 fcitx5-rime
cd ~/build
curl -fsSL https://raw.githubusercontent.com/rime/plum/master/rime-install \
  | bash
cd plum
rime_frontend=fcitx5-rime bash rime-install array emoji

# audio
pacman -S pipewire pipewire-jack pipewire-pulse pipewire-audio \
  wireplumber  

# fonts
yay -S noto-fonts-emoji noto-fonts-tc noto-fonts-sc otf-cascadia-code-nerd


# discord
yay -S discord betterdiscord-installer 

# system info
pacman -S neofetch btop

# ssh
pacman -S openssh

# screenshot / screensharing
yay -S grimblast grim slurp

# waybar
yay -S waybar-hyprland-git
# pip install gpustat pyroute2

# notification
pacman dunst

# neovim
bash .config/nvim/bootstarp.sh
