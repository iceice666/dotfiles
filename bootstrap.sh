
sudo pacman -S lolcat neofetch zsh exa
chsh -s $(which zsh)
curl -sL --proto-redir -all,https https://raw.githubusercontent.com/zplug/installer/master/installer.zsh | zsh
python3 -m pip install pipx
pipx install pls
