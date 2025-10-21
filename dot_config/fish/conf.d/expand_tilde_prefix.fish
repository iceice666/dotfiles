function _expand_tilde_prefix
    set -l token (commandline -t)

    if string match -q -r '~[a-zA-Z0-9_.-]' -- $token
        commandline -t (string replace -r '^~' "~/" -- $token)
        commandline -f repaint
    else
        commandline -f complete  # Trigger normal tab completion
    end
end

bind tab '_expand_tilde_prefix'