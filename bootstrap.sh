# zsh + zplug
sudo pacman -S zsh exa
chsh -s $(which zsh)
curl -sL --proto-redir -all,https https://raw.githubusercontent.com/zplug/installer/master/installer.zsh | zsh

# yay
sudo pacman -S --needed git base-devel
mkdir ~/build
cd ~/build
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si

# hyprland
yay -S hyprland hyprpaper-git

# fcitx5 & rime
sudo pacman fcitx5 fcitx5-rime
cd ~/build
curl -fsSL https://raw.githubusercontent.com/rime/plum/master/rime-install | bash
cd plum
rime_frontend=fcitx5-rime bash rime-install array emoji

# discord
yay -S discord betterdiscord-installer 

# fonts
yay -S noto-fonts-emoji noto-fonts-tc
yay -S otf-cascadia-code-nerd

# neovim
cd ~/.config
git clone https://github.com/iceice666/nvim.git
bash nvim/bootstarp.sh

# misc
sudo pacman -S neofetch lazygit openssh btop
