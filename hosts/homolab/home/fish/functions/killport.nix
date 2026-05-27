{ ... }:

{
  programs.fish.functions.killport = {
    description = "Kill process running on specified port";
    body = ''
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
      else if type -q fuser
          fuser -k $port_num/tcp
          and echo "Killed process on port $port_num"
          or echo "No process found on port $port_num"
      else
          echo "Neither lsof nor fuser found"
          return 1
      end
    '';
  };
}
