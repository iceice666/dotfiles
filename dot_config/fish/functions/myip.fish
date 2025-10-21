function myip --description "Get your public IP address"
    if type -q curl
        echo "Public IP:"
        curl -s ifconfig.me
        echo ""
        echo "Local IP:"
        ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}'
    else
        echo "curl is required for myip function"
        return 1
    end
end