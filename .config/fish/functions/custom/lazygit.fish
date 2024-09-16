function lazygit
  if test $PWD = $HOME
    command lazygit --git-dir="$HOME/.dotfiles.git" --work-tree=$HOME $argv
  else
    command lazygit $argv
  end
end


