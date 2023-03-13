# git
sudo pacman -S git lazygit

# zsh + zplug
sudo pacman -S zsh exa
chsh -s $(which zsh)
curl -sL --proto-redir -all,https \
  https://raw.githubusercontent.com/zplug/installer/master/installer.zsh | zsh

# yay
sudo pacman -S --needed git base-devel
mkdir ~/build
cd ~/build
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si

# hyprland
yay -S hyprland hyprpaper-git xdg-desktop-portal-hyprland-git
sudo pacman -S kitty fuzzel firefox

# fcitx5 & rime
sudo pacman fcitx5 fcitx5-rime
cd ~/build
curl -fsSL https://raw.githubusercontent.com/rime/plum/master/rime-install \
  | bash
cd plum
rime_frontend=fcitx5-rime bash rime-install array emoji

# audio
sudo pacman -S pipewire pipewire-jack pipewire-pulse pipewire-audio \
  wireplumber  

# fonts
yay -S noto-fonts-emoji noto-fonts-tc noto-fonts-sc otf-cascadia-code-nerd

# neovim
bash .config/nvim/bootstarp.sh

# discord
yay -S discord betterdiscord-installer 

# system info
sudo pacman -S neofetch btop

# ssh
sudo pacman -S openssh

# screenshot / screensharing
yay -S grimblast grim slurp

# waybar
pacman -S waybar
# pip install gpustat pyroute2
