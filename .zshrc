# cd to $HOME
cd $HOME

source $HOME/.utils


# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Lines configured by zsh-newuser-install
bindkey -v
# End of lines configured by zsh-newuser-install
# The following lines were added by compinstall
zstyle :compinstall filename '/home/iceice666/.zshrc'

autoload -Uz compinit
compinit
# End of lines added by compinstall



# Start of custom alias

alias wrappedhl='$HOME/.config/hypr/wrappedhl'


alias plz='sudo'

alias lg="lazygit"

alias l=' exa -almhF --time-style iso -s type --icons --git-ignore'
alias ll='exa -almhF --time-style iso -s type --icons '
alias lt='exa -almhF --time-style iso -s type --icons --git-ignore --tree -L 3 -I .git'

alias dotfiles='git --git-dir=$HOME/.dotfiles.git/ --work-tree=$HOME'
alias dotlg='lazygit --git-dir=$HOME/.dotfiles.git/ --work-tree=$HOME'

alias rm='rm -r'
alias cp='cp -r'
alias mkdir='mkdir -p'

alias ..='cd ..'
alias home='cd ~'

alias nv='nnvim'
alias vim='nnvim'

alias pm='sudo pacman'
alias pms='sudo pacman -S'
alias pmr='sudo pacman -R'
alias pmu='sudo pacman -Syu'


alias self='neofetch | lolcat'

alias nvcfg='nnvim -c "cd ~/.config/nvim"'

alias wrappedhl="~/.config/hypr/wrappedhl"
alias chadwm="startx ~/dwm/chadwm/scripts/run.sh"
alias dwm="startx ~/dwm/dwm/run.sh"

alias reload='unalias -a ; source ~/.zshrc ; cd - '
# End of custom alias



# Start of zplug settings
export ZSH_LS_DISABLE_GIT=false

source ~/.zplug/init.zsh

zplug "zsh-users/zsh-completions"
zplug "zsh-users/zsh-history-substring-search"
zplug "zsh-users/zsh-autosuggestions"
zplug "zdharma/fast-syntax-highlighting"
zplug "hlissner/zsh-autopair"
zplug "djui/alias-tips"
# zplug "b4b4r07/enhancd", use:init.sh
zplug "jeffreytse/zsh-vi-mode"
zplug "ael-code/zsh-colored-man-pages"
zplug "Freed-Wu/zsh-command-not-found"
zplug "plugins/sudo", from:oh-my-zsh
zplug "plugins/extract", from:oh-my-zsh

zplug "romkatv/powerlevel10k", as:theme, depth:1

if ! zplug check --verbose; then
  printf "Install? [y/N]: "
  if read -q; then
    echo; zplug install
  fi
fi

zplug load
# End of zplug settings


# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

export NVM_DIR="$HOME/.config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

