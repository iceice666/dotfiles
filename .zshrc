# cd to $HOME
cd ~



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
alias plz='sudo'

alias lg="lazygit"

alias l='exa -1aalmhF --git --time-style iso -s type --git-ignore --icons'
alias ll='exa -1aalmhF --git --time-style iso -s type --icons '
alias lt='exa -1almhFT --git -L 3 -I .git --time-style iso -s type --git-ignore --icons'

alias rm='rm -r'
alias cp='cp -r'
alias mkdir='mkdir -p'

alias ..='cd ..'

alias nv='nvim'
alias vim='nvim'
alias vi='nvim'
alias emacs='nvim'

alias pm='sudo pacman'
alias pms='sudo pacman -S'
alias pmr='sudo pacman -R'
alias pmu='sudo pacman -Syu'

alias yas='yay -S'
alias yar='yay -R'

alias self='neofetch | lolcat'

alias dotfile='nvim -c "cd ~"'
alias config='nvim -c "cd ~/.config"'
alias nvcfg='nvim -c "cd ~/.config/nvim"'

alias wrappedhl="~/.config/hypr/wrappedhl"

alias reload='source ~/.zshrc'
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
zplug "b4b4r07/enhancd", use:init.sh
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

