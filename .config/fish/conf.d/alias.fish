

# cat alternative
alias cat="bat"

alias plz='sudo'

# ls
alias l='eza -almhF --time-style iso -s type --icons --git-ignore'
alias ll='eza -almhF --time-style iso -s type --icons'
alias lt='eza -almhF --time-style iso -s type --icons --git-ignore --tree -L 3 -I .git'

# file operation: add recursive as default


alias nvcfg='nvim -c "cd ~/.config/nvim"'

# package manager
alias pm='paru'
alias pms='paru -S'
alias pmr='paru -R'
alias pmu='paru -Syu'
alias pmq='paru -Q | rg'

# lazygit
alias lg='lazygit'
alias dotlg='lazygit --git-dir=$HOME/.dotfiles.git --work-tree=$HOME'

# filemanager
alias fm='yazi'

# End of custom aliases
