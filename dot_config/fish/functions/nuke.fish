function nuke -d "Remove folder/file with confirmation. If no path specified, nuke current folder and go to parent"
    # Determine target path
    if test (count $argv) -eq 0
        set target (pwd)
        set go_parent true
    else
        set target $argv[1]
        set go_parent false
    end

    # Resolve to absolute path for clarity
    set target (realpath $target 2>/dev/null; or echo $target)

    # Prompt for confirmation
    read -l confirm -P "Are you sure to nuke $target? [y/N] "

    if test "$confirm" = "y" -o "$confirm" = "Y"
        if $go_parent
            # Save parent directory before nuking current
            set parent (dirname $target)
            cd $parent
            rm -rf $target
            echo "Nuked $target and moved to $parent"
        else
            rm -rf $target
            echo "Nuked $target"
        end
    else
        echo "Aborted."
    end
end
