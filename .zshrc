# cd to $HOME
cd ~

# PATH
export PATH="/home/iceice666/.local/bin:$PATH"

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

# Start of zplug settings
source ~/.zplug/init.zsh

# theme
zplug "romkatv/powerlevel10k", as:theme, depth:1

# ls when cd a dir
zplug "aikow/zsh-auto-ls"


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

# Start of custom alias
alias l='pls -d all'
alias ll='pls -a -d all'

alias pip='python -m pip'

alias plz='sudo'

alias nv='nvim'
alias vim='nvim'
alias vi='nvim'
alias emacs='nvim'

alias pm='sudo pacman'
alias pms='sudo pacman -S'
alias pmr='sudo pacman -R'

alias yas='yay -S'
alias yar='yay -R'
# End of custom alias

