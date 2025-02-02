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

printdog(){
  echo "no dog"
}

mcd  ()
{
  mkdir -p "$1"
  cd "$1" || return
}


git()
{
  if [[ $PWD = $HOME ]]; then
    command git --git-dir=$HOME/.dotfiles.git --work-tree=$HOME "$@"
  else
    command git "$@"
  fi
}

lazygit()
{
  if [[ $PWD = $HOME ]]; then
    command lazygit --git-dir=$HOME/.dotfiles.git --work-tree=$HOME "$@"
  else
    command lazygit "$@"
  fi
}

# End of custom funciton
