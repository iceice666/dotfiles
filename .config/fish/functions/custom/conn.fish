function conn --description "Connect wifi with nmcli"

  if test (count $argv) -lt 1
    echo "Missing wifi SSID."
    return 1
  end

  if not type -q nmcli
    echo "Command 'nmcli' is missing"
    return 1
  end

  set -l counter 0
  while test $counter -lt 10 
    nmcli device wifi rescan
    nmcli device wifi connect "$argv[1]" > /dev/null 2>&1

    if test $status -eq 0
      echo "Connect to wifi $argv[1]"
      return 0
    end

    set counter $(match $counter + 1)
    sleep 1
  end

  echo "Cannot connect to wifi $argv[1] now."
  return 1

end
