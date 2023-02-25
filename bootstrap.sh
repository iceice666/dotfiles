
sudo pacman -S lolcat neofetch zsh exa lazygit
chsh -s $(which zsh)
curl -sL --proto-redir -all,https https://raw.githubusercontent.com/zplug/installer/master/installer.zsh | zsh

sudo pacman -S --needed git base-devel
mkdir ~/build
cd ~/build
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si

yay -S hyprland
