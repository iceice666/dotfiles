function git
  if test $PWD = $HOME
    command git --git-dir="$HOME/.dotfiles.git" --work-tree=$HOME $argv
  else
    command git $argv
  end
end


