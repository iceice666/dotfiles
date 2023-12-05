
[private]
help:
  @just --list

ensure := "sudo pacman -S --needed"
aur_ensure := "paru -S --needed"
build := "$HOME/build"
bash_cfg := "set -euxo pipefail "

[private]
first-deploy: 
  #!/usr/bin/env bash
  {{bash_cfg}}

  # make a dir for build
  mkdir $HOME/build

  # pacman update
  sudo pacman -Syu
  
  {{ensure}} lazygit exa zsh openssh btop 

  
  # zsh + zplug + starship
  chsh -s /usr/bin/zsh
  curl -sL --proto-redir -all,https \
  https://raw.githubusercontent.com/zplug/installer/master/installer.zsh | zsh
  curl -sS https://starship.rs/install.sh | sh
  

  # init language compilers
  {{ensure}} rustup python3 npm
  rustup default stable

  # install paru
  just paru

  # now we can install some aur packages
  {{aur_ensure}} c-lolcat # lolcat c implementation



# text editor
neovim:
  #!/usr/bin/env bash
  {{bash_cfg}}

  {{ensure}} neovim

  cd $HOME/.config/nvim
  git pull
  just deploy


# aur manager
[no-cd]
[private]
paru: 
  #!/usr/bin/env bash
  {{bash_cfg}}

  cd {{build}}

  sudo pacman -S --needed base-devel 

  git clone https://aur.archlinux.org/paru.git
  cd paru 
  makepkg -si




    

