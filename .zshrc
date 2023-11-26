# cd to $HOME
cd $HOME


# Start of custom alias
alias yee='nmcli device wifi rescan; nmcli device wifi connect \ ∫\ dx\ \(x\^5+1\)\^\(-1\)\ =\ \?+c'

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


# End of custom alias


# Start of custom funciton

mcd  ()
{
  mkdir -p "$1"
  cd "$1" || return
}

nnvim ()
{
  while true; do
    nvim "$@"  # change path to real nvim binary as necessary
    if [ $? -ne 1 ]; then
        break
    fi
  done
}


# End of custom funciton


# Lines configured by zsh-newuser-install
bindkey -e
# End of lines configured by zsh-newuser-install
# The following lines were added by compinstall
zstyle :compinstall filename '/home/iceice666/.zshrc'

autoload -Uz compinit
compinit
# End of lines added by compinstall

# Start of zplug settings
export ZSH_LS_DISABLE_GIT=false

source ~/.zplug/init.zsh

zplug "zsh-users/zsh-completions"
zplug "zsh-users/zsh-history-substring-search"
zplug "zsh-users/zsh-autosuggestions"
zplug "zdharma/fast-syntax-highlighting"
zplug "hlissner/zsh-autopair"
zplug "djui/alias-tips"
zplug "ael-code/zsh-colored-man-pages"
zplug "Freed-Wu/zsh-command-not-found"
zplug "plugins/sudo", from:oh-my-zsh
zplug "plugins/extract", from:oh-my-zsh


if ! zplug check --verbose; then
  printf "Install? [y/N]: "
  if read -q; then
    echo; zplug install
  fi
fi

zplug load
# End of zplug settings


export NVM_DIR="$HOME/.config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion


eval "$(starship init zsh)"


# pnpm
export PNPM_HOME="/home/iceice666/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
