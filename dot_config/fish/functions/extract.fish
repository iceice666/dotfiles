function extract --description "Extract various archive formats"
    if test (count $argv) -eq 0
        echo "Usage: extract <file>"
        return 1
    end
    
    set -l file $argv[1]
    
    if not test -f $file
        echo "File not found: $file"
        return 1
    end
    
    switch $file
        case "*.tar.bz2"
            tar xjf $file
        case "*.tar.gz"
            tar xzf $file
        case "*.tar.xz"
            tar xJf $file
        case "*.bz2"
            bunzip2 $file
        case "*.rar"
            unrar x $file
        case "*.gz"
            gunzip $file
        case "*.tar"
            tar xf $file
        case "*.tbz2"
            tar xjf $file
        case "*.tgz"
            tar xzf $file
        case "*.zip"
            unzip $file
        case "*.Z"
            uncompress $file
        case "*.7z"
            7zz x $file
        case "*"
            echo "Unsupported archive format: $file"
            return 1
    end
    
    echo "Extracted: $file"
end
