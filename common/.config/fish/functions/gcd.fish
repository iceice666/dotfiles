function gcd --description "Git clone repository and change into it"
    if test (count $argv) -eq 0
        echo "Usage: gcd <repository-url> [directory-name]"
        return 1
    end
    
    set repo_url $argv[1]
    
    # Extract directory name from repo URL if not provided
    if test (count $argv) -eq 2
        set dir_name $argv[2]
    else
        # Extract repo name from URL (remove .git suffix if present)
        set dir_name (basename $repo_url .git)
    end
    
    if not git clone $repo_url $dir_name
        echo "Failed to clone repository: $repo_url"
        return 1
    end
    
    cd $dir_name
end