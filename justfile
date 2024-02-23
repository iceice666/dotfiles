
[private]
help:
  @just --list

ensure := "sudo pacman -Syu --needed"
aur_ensure := "paru -S --needed"
build := "$HOME/build"
bash_cfg := "set -euxo pipefail "
dotgit := "git --git-dir=$HOME/.dotfiles.git/ --work-tree=$HOME"

deploy:
  #!/usr/bin/env bash
  {{bash_cfg}}

  # make a dir for build
  mkdir $HOME/build

  {{ensure}} lazygit exa zsh openssh btop ripgrep bat


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

  git clone git@github.com:iceice666/nvim.git $HOME/.config/nvim

  cd $HOME/.config/nvim
  git checkout main
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
  mkdir $HOME/.dotfiles.git

  git clone --bare https://github.com/iceice666/dotfiles.git $HOME/.dotfiles.git
  {{dotgit}} fetch --all
  {{dotgit}} reset --hard origin/master
  {{dotgit}} remote set-url origin git@github.com:iceice666/dotfiles.git
  ssh-keygen

# hyprland
hyprland:
  #!/usr/bin/env bash
  {{bash_cfg}}

  git clone git@github.com:iceice666/hyprland.git $HOME/.config/hypr

  cd $HOME/.config/hypr
  git checkout master
  git pull
  just deploy


# niri
niri:
  #!/usr/bin/env bash
  {{bash_cfg}}

  {{ensure}} pipewire pipewire-{alsa,jack,pulse} wireplumber noto-fonts-cjk \
                 kitty fuzzel firefox swaylock mako \
                 xdg-desktop-portal-gnome gnome-keyring gdm

  {{aur_ensure}} ttf-cascadia-code-nerd niri

