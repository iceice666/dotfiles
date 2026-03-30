{ dotfiles, ... }:

{
  environment.etc."docker/certs.d/code.justaslime.dev/ca.crt".source =
    dotfiles + /sensitive/hosts/server/cloudflare-origin-ca/root-rsa-cert.pem;

  virtualisation.docker = {
    enable = true;

    daemon.settings = {
      bip = "172.17.0.1/16";
      dns = [ "172.17.0.1" ];
      hosts = [
        "unix:///var/run/docker.sock"
        "tcp://127.0.0.1:2375"
      ];
    };
  };
}
