{
  config,
  dotfiles,
  lib,
  pkgs,
  ...
}:

let
  wifiPskPath = config.sops.secrets.lumo-wifi-psk.path;
in
{
  home.packages = [
    pkgs.iw
    pkgs.wpa_supplicant
  ];

  sops.secrets.lumo-wifi-psk = {
    sopsFile = dotfiles + /sensitive/hosts/lumo/wifi.yaml;
    key = "psk";
    mode = "0400";
  };

  home.activation.lumoWifi = lib.hm.dag.entryAfter [ "sopsAlpine" ] ''
    # Alpine's ifupdown-ng Wi-Fi hook and OpenRC service use system paths.
    # Keep the required packages installed outside the Home Manager profile so
    # networking can start before /root is available.
    /sbin/apk add --no-cache iw wpa_supplicant ifupdown-ng-wifi >/dev/null

    install -d -m 0700 /etc/wpa_supplicant
    {
      printf '%s\n' 'ctrl_interface=DIR=/run/wpa_supplicant GROUP=wheel'
      printf '%s\n' 'update_config=0'
      printf '%s\n' 'network={'
      printf '%s\n' '    ssid="Home wifi"'
      printf '    psk=%s\n' "$(cat '${wifiPskPath}')"
      printf '%s\n' '}'
    } > /etc/wpa_supplicant/wpa_supplicant.conf
    chmod 0600 /etc/wpa_supplicant/wpa_supplicant.conf

    cat > /etc/conf.d/wpa_supplicant <<'EOF'
    wpa_supplicant_args="-i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf"
    wpa_supplicant_dbus=no
    EOF

    cat > /etc/network/interfaces <<'EOF'
    auto lo
    iface lo inet loopback
    iface lo inet6 loopback

    auto wlan0
    iface wlan0 inet static
      address 192.168.1.128/24
      gateway 192.168.1.1

    iface eth0 inet manual
    EOF

    /sbin/rc-update add networking boot
    /sbin/rc-update add wpa_supplicant boot
    /sbin/rc-update del networking default 2>/dev/null || true

    # Do not restart networking from Home Manager activation: deploy-rs uses
    # the current SSH connection. The live migration is handled separately;
    # this configuration owns subsequent boots.
  '';
}
