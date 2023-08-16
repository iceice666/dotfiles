#! /usr/bin/env bash

# ensure just and git have been installed
sudo pacman -S just git

# create dir for bare repo
mkdir ~/.dotfiles.git

# clone
git clone --bare https://github.com/iceice666/dotfiles.git ~/.dotfiles.git

git --git-dir=$HOME/.dotfiles.git/ --work-tree=$HOME checkout

# use ssh to do job
git remote set-url origin git@github.com:iceice666/dotfiles.git

# init 
just first-deploy
