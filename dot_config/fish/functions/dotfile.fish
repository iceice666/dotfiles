function dotfile --description "Dotfile manager"
    if not command -q chezmoi
        echo "You have to install chezmoi to use this script"
        return 1
    end

    if test (count $argv) -eq 0
        echo "Usage: dotfile <edit|diff|apply|lazygit>"
        return 1
    end

    set -l mode $argv[1]

    switch $mode
        case "edit"
            # Check for a valid and executable $EDITOR
            set -l editor_cmd (command -s $EDITOR)
            if test -x "$editor_cmd"
                "$editor_cmd" (chezmoi source-path)
            else
                echo "Please set a valid and executable \$EDITOR environment variable."
                return 1
            end
        case "diff"
            chezmoi diff
        case "apply"
            chezmoi apply
        case "lazygit"
            if command -q lazygit
                lazygit --path (chezmoi source-path)
            else
                echo "You have to install Lazygit to use this operation."
                return 1
            end
        case "*"
            echo "Unknown operation: '$mode'. Usage: dotfile <edit|diff|apply|lazygit>"
            return 1
    end
    # Ensure a successful exit if one of the cases ran successfully
    return 0
end
