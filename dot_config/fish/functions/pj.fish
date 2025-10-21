function pj --description "Jump to project directory"
    if test (count $argv) -ne 1
        echo "Usage: pj <project-name>"
        return 1
    end
    
    if not test -d $ProjectDir
        echo "Project directory not found: $ProjectDir"
        return 1
    end
    
    set target $ProjectDir/$argv[1]
    if not test -d $target
        echo "Project not found: $target"
        echo "Available projects:"
        ls $ProjectDir 2>/dev/null | head -10
        return 1
    end
    
    cd $target
end