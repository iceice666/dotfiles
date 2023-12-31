
[private]
help:
  @just --list

ensure := "sudo pacman -S --needed"
aur_ensure := "paru -S --needed"
build := "$HOME/build"
bash_cfg := "set -euxo pipefail "
dotgit := "git --git-dir=$HOME/.dotfiles.git/ --work-tree=$HOME"

[private]
deploy: 
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
  sudo npm install -g pnpm

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


# git
[no-cd]
[private]
git:
  #!/usr/bin/env bash
  {{bash_cfg}}
  sudo pacman -S --needed git openssh
  mkdir $HOME/.dotfiles.giw 

  git clone --bare https://github.com/iceice666/dotfiles.git $HOME/.dotfiles.git
  {{dotgit}} checkout
  {{dotgit}} remote set-url origin git@github.com:iceice666/dotfiles.git
  ssh-keygen

