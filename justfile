
[private]
help:
  @just --choose

ensure := "sudo pacman -S --needed"
aur_ensure := "paru -S --needed"
build := "$HOME/build"
bash_cfg := "set -euxo pipefail ; source $HOME/.utils"

[private]
first-deploy: 
  #!/usr/bin/env bash
  {{bash_cfg}}

  # make a dir for build
  mkdir $HOME/build

  # pacman update
  sudo pacman -Syu
  
  # git
  {{ensure}} lazygit 
  
  # zsh + zplug
  {{ensure}} zsh exa
  chsh -s /usr/bin/zsh
  curl -sL --proto-redir -all,https \
  https://raw.githubusercontent.com/zplug/installer/master/installer.zsh | zsh
  
  # ssh
  {{ensure}} openssh

  # install paru
  just paru

  # now we can install some aur packages
  {{aur_ensure}} c-lolcat




neovim:
  #!/usr/bin/env bash
  {{bash_cfg}}

  {{ensure}} neovim

  cd $HOME/.config/nvim
  git pull
  just first-deploy


[no-cd]
paru: # aur manager
  #!/usr/bin/env bash
  {{bash_cfg}}

  cd {{build}}

  sudo pacman -S --needed base-devel
  git clone https://aur.archlinux.org/paru.git paru --force
  cd paru 
  makepkg -si


#
# For pacakges
#

hyprland:
  {{ensure}} hyprland
