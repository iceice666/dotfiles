#! /usr/bin/env bash

# ensure requirement have been installed
sudo pacman -S just git openssh --needed

# create dir for bare repo
mkdir ~/.dotfiles.git

# clone
git clone --bare https://github.com/iceice666/dotfiles.git ~/.dotfiles.git


git --git-dir=$HOME/.dotfiles.git/ --work-tree=$HOME  checkout

# init submodules
git --git-dir=$HOME/.dotfiles.git/ --work-tree=$HOME  submodule init

# use ssh to do job
git --git-dir=$HOME/.dotfiles.git/ --work-tree=$HOME  remote set-url origin git@github.com:iceice666/dotfiles.git

ssh-keygen

# init 
just first-deploy
