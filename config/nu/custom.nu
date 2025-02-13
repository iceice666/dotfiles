#
# Custom function/commands
#

# Summon a cat
def "print cat" [] {
    echo 'Here is your cat.'
    echo ''
    echo '            A____A    '
    echo '           /*    *\   '
    echo '          {   _  _ }  '
    echo '          A\` >  v /< '
    echo '        / !!!!! !!}   '
    echo '       / ! \!!!!! |   '
    echo '  ____{   ) |  |  |   '
    echo ' / ___{ !!c |  |  |   '
    echo '{ (___ \__\__@@_)@_)  '
    echo ' \____)               '
    echo 'Paradise is no longer paradise if there is no cat.'
}

# Summon a dog, currently, unavailable
def "print dog" [] {
    echo "no dog unavailable"
}

# Make dir then change directory into it
def mcd [path: string] {
    mkdir $"($path)"
    cd $"($path)"
}

# Jump into directory under project dir
def pj [project: string] {
    cd $"($env.ProjectDir)/($project)"
}

# Init the development environment
def devenv-init [lang: string] {
    let url = $"https://flakehub.com/f/the-nix-way/dev-templates/*#($lang)"
    nix flake init --template $"($url)"
}

#
# Aliases
#

alias l = eza -almhF --time-style iso -s type --git-ignore
alias ll = eza -almhF --time-style iso -s type
alias lt = eza -almhF --time-style iso -s type --git-ignore --tree -L 3 -I .git
alias llt = eza -almhF --time-style iso -s type --tree -L 3
alias lg = lazygit
alias cat = bat
alias nano = nvim
alias vim = nvim
