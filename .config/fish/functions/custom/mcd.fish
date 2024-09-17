function mcd --description "mkdir and cd"
    if test (count $argv) -lt 1
        echo "Error: Missing directory name."
        return 1
    end
    mkdir -p "$argv"
    cd "$argv" || return
end
