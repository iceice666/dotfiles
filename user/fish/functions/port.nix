{ ... }:

{
  programs.fish.functions.port = {
    description = "Find what's running on a specific port";
    body = ''
      if test (count $argv) -eq 0
          echo "Usage: port <port-number>"
          return 1
      end

      set -l port_num $argv[1]

      if type -q lsof
          lsof -i :$port_num
      else if type -q netstat
          netstat -tulpn | grep :$port_num
      else
          echo "Neither lsof nor netstat found"
          return 1
      end
    '';
  };
}
