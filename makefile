
env:
	cd ~
	sudo pacman -Sy
# git
	sudo pacman -S git lazygit 

# zsh + zplug
	sudo pacman -S zsh exa
	chsh -s $(which zsh)
	curl -sL --proto-redir -all,https \
  https://raw.githubusercontent.com/zplug/installer/master/installer.zsh | zsh

.PHONY: env

basic: yay

# fcitx5 & rime
	sudo pacman -S fcitx5 fcitx5-rime fcitx5-config-qt
	cd ~/build
	curl -fsSL https://raw.githubusercontent.com/rime/plum/master/rime-install | bash
	cd plum
	rime_frontend=fcitx5-rime bash rime-install array emoji

# audio
	sudo pacman -S pipewire pipewire-jack pipewire-pulse pipewire-audio wireplumber  

# fonts
	yay -S noto-fonts-emoji noto-fonts-tc noto-fonts-sc otf-cascadia-code-nerd

# system info
	sudo pacman -S neofetch btop

# ssh
	sudo pacman -S openssh

# notification
	sudo pacman dunst

.PHONY: basic


hyprland: yay
# hyprland
	yay -S xdg-desktop-portal-wlr 
	yay -S xdg-desktop-portal-hyprland-git  hyprland 
	sudo pacman -S kitty fuzzel firefox

# screenshot / screensharing
	yay -S grimblast grim slurp

.PHONY: hyprland

discord:yay
# discord
	yay -S discord betterdiscord-installer 

.PHONY: discord

neovim: yay
	yay -S neovim-nightly
	cd ~/.config && git clone https://github.com/iceice666/nvim
	bash ~/.config/nvim/bootstarp.sh

.PHONY: neovim

yay: build/yay-bin
.PHONY: yay

build/yay-bin:
	# yay
	sudo pacman -S --needed git base-devel
	mkdir ~/build
	cd ~/build
	git clone https://aur.archlinux.org/yay-bin.git
	cd yay-bin
	makepkg -si
