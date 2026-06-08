{ ... }:

{
  programs.fish.functions.myip = {
    description = "Get your public IP address";
    body = ''
      if type -q curl
          echo "Public IP:"
          curl -s ifconfig.me
          echo ""
          echo "Local IP:"
          if type -q ifconfig
              ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}'
          else if type -q ip
              ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | string replace -r '/.*' ""
          else
              echo "(unable to detect local IP)"
          end
      else
          echo "curl is required for myip function"
          return 1
      end
    '';
  };
}
