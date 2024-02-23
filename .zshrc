# Start of Znap settings

# Download Znap, if it's not there yet.
[[ -r $HOME/znap/znap/znap.zsh ]] ||
    git clone --depth 1 -- \
        https://github.com/marlonrichert/zsh-snap.git $HOME/znap/znap

source ~/znap/znap/znap.zsh  # Start Znap

znap source marlonrichert/zsh-autocomplete
znap source marlonrichert/zsh-edit

znap source zsh-users/zsh-syntax-highlighting
znap source hlissner/zsh-autopair
znap source djui/alias-tips
znap source ael-code/zsh-colored-man-pages
znap source Freed-Wu/zsh-command-not-found

znap source ohmyzsh/ohmyzsh plugins/{git,sudo,extract}

# End of Znap settings

# Start of custom funciton

printcat()
{
  echo "Here is your cat.     "
  echo " "
  echo "            A____A    "
  echo "           /*    *\   "
  echo "          {   _  _ }  "
  echo "          A\` >  v /< "
  echo "        / !!!!! !!}   "
  echo "       / ! \!!!!! |   "
  echo "  ____{   ) |  |  |   "
  echo " / ___{ !!c |  |  |   "
  echo "{ (___ \__\__@@_)@_)  "
  echo " \____)               "
  echo "Paradise is no longer paradise if there is no cat."
}

mcd  ()
{
  mkdir -p "$1"
  cd "$1" || return
}

nvim ()
{
  while true; do
    command nvim "$@"  # change path to real nvim binary as necessary
    if [ $? -ne 1 ]; then
        break
    fi
  done
}

neovide ()
{
  while true; do
    command neovide "$@"
    if [ $? -ne 1 ]; then
      break
    fi
  done
}

conn()
{
  err_count=0
  while true; do
    nmcli device wifi rescan
    nmcli device wifi connect "$1" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo "Connected to wifi $1."
      break
    fi
    if [ $err_count -gt 10 ]; then
      echo "Cannot connect to wifi $1 right now."
      break
    fi
    err_count=$((err_count + 1))
    sleep 1
  done
}

git()
{
  if [[ $PWD = $HOME ]]; then
    command git --git-dir=$HOME/.dotfiles.git --work-tree=$HOME "$@"
  else
    command git "$@"
  fi
}

# End of custom funciton
# Start of custom alias

# network connection
alias yee='conn Yee'

alias cat="bat"

alias plz='sudo'

alias l='exa -almhF --time-style iso -s type --icons --git-ignore'
alias ll='exa -almhF --time-style iso -s type --icons '
alias lt='exa -almhF --time-style iso -s type --icons --git-ignore --tree -L 3 -I .git'

alias rm='rm -r'
alias cp='cp -r'
alias mkdir='mkdir -p'

alias ..='cd ..'
alias home='cd ~'

alias nv='nvim'
alias vim='nvim'

alias pm='paru'
alias pms='paru -S'
alias pmr='paru -R'
alias pmu='paru -Syu'
alias pmq='paru -Q | rg'


alias self='neofetch | lolcat'

alias nvcfg='nvim -c "cd ~/.config/nvim"'

alias cat='bat'

alias lg='lazygit'
alias dotlg='lazygit --git-dir=$HOME/.dotfiles.git --work-tree=$HOME '

# End of custom alias



# custom keybind
# bindkey -v # vi mode
bindkey "\e[1~" beginning-of-line # Home
bindkey "\e[4~" end-of-line # End
bindkey "\e[5~" beginning-of-history # PageUp
bindkey "\e[6~" end-of-history # PageDown
bindkey "\e[2~" quoted-insert # Ins
bindkey "\e[3~" delete-char # Del
bindkey "\e[5C" forward-word
bindkey "\eOc" emacs-forward-word
bindkey "\e[5D" backward-word
bindkey "\eOd" emacs-backward-word
bindkey "\e\e[C" forward-word
bindkey "\e\e[D" backward-word
bindkey "\e[Z" reverse-menu-complete # Shift+Tab
# End of custom keybind


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

# Generated for envman. Do not edit.


clear
[ -s "$HOME/.config/envman/load.sh" ] && source "$HOME/.config/envman/load.sh"
