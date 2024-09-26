function notify --description "Send a notification on MacOS"
    # Check if the system is Darwin (macOS)
    if test (uname) != "Darwin"
        return
    end

    # Get the number of arguments
    set __ac (count $argv)

    # Set default values for title and description
    set title ""
    set desc "hello world"

    # Handle argument logic
    if test $__ac -ge 2
        set title $argv[2]
        set desc $argv[1]
    else if test $__ac -ge 1
        set desc $argv[1]
    end

    # Display the notification using osascript
    osascript -e "display notification \"$desc\" with title \"$title\""
end
