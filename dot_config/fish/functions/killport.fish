function killport --description "Kill process running on specified port"
    if test (count $argv) -eq 0
        echo "Usage: killport <port-number>"
        return 1
    end
    
    set -l port_num $argv[1]
    
    if type -q lsof
        set -l pid (lsof -ti :$port_num)
        if test -n "$pid"
            echo "Killing process $pid on port $port_num"
            kill -9 $pid
        else
            echo "No process found on port $port_num"
        end
    else
        echo "lsof is required for killport function"
        return 1
    end
end