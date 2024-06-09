

# cat alternative
alias cat="bat"
alias catt="command cat"

alias plz='sudo'

# ls
alias l='exa -almhF --time-style iso -s type --icons --git-ignore'
alias ll='exa -almhF --time-style iso -s type --icons'
alias lt='exa -almhF --time-style iso -s type --icons --git-ignore --tree -L 3 -I .git'

# file operation: add recursive as default
alias rm='rm -r'
alias cp='cp -r'
alias mkdir='mkdir -p'

# neovim
alias nv='nnvim'
alias vim='nnvim'
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
