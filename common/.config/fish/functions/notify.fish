function notify --description "Send notification when command completes"
    if test (count $argv) -eq 0
        echo "Usage: notify <command>"
        return 1
    end
    
    set -l start_time (date +%s)
    set -l cmd $argv
    
    echo "Running: $cmd"
    eval $cmd
    set -l exit_code $status
    
    set -l end_time (date +%s)
    set -l duration (math $end_time - $start_time)
    
    if test $exit_code -eq 0
        set -l message "✅ Command completed successfully in {$duration}s"
    else
        set -l message "❌ Command failed with exit code $exit_code in {$duration}s"
    end
    
    echo $message
    
    # macOS notification
    if type -q osascript
        osascript -e "display notification \"$message\" with title \"Command Finished\""
    end
    
    # Linux notification
    if type -q notify-send
        notify-send "Command Finished" "$message"
    end
    
    return $exit_code
end