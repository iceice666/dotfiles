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
    mkdir path
    cd path
}
