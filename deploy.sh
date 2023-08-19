#! /usr/bin/env bash

# ensure requirement have been installed
sudo pacman -S just git openssh --needed

# create dir for bare repo
mkdir ~/.dotfiles.git

# clone
git clone --bare https://github.com/iceice666/dotfiles.git ~/.dotfiles.git

alias dotfiles='git --git-dir=$HOME/.dotfiles.git/ --work-tree=$HOME '

dotfiles checkout

# use ssh to do job
dotfiles remote set-url origin git@github.com:iceice666/dotfiles.git

ssh-keygen

# init 
just first-deploy
