{
  config,
  lib,
  pkgs,
  ...
}:

{
  sops.age = {
    keyFile = "/var/lib/sops-nix/key.txt";
    sshKeyPaths = lib.mkForce [ ];
  };
  sops.defaultSecretsMountPoint = "/var/lib/sops-nix/secrets.d";
  sops.defaultSymlinkPath = "/var/lib/sops-nix/secrets";
  home.sessionVariables.SOPS_AGE_KEY_CMD = lib.mkForce "cat /var/lib/sops-nix/key.txt";

  home.activation.verifyAlpineRoot = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
    if [ "$(id -u)" -ne 0 ]; then
      echo "Alpine Home Manager activation must run as root." >&2
      exit 1
    fi

    if [ ! -r /etc/os-release ] || ! grep -qx 'ID=alpine' /etc/os-release; then
      echo "This Home Manager profile requires Alpine Linux." >&2
      exit 1
    fi
  '';

  home.activation.configureAlpineTrust =
    lib.hm.dag.entryBetween [ "configureAlpineRoot" "sopsAlpine" ] [ "writeBoundary" ]
      ''
        if ! /sbin/apk info -e ca-certificates >/dev/null 2>&1; then
          /sbin/apk add --no-cache ca-certificates
        fi

        if [ ! -r /etc/ca-certificates.conf ] || [ ! -x /usr/sbin/update-ca-certificates ]; then
          echo "Alpine ca-certificates configuration or update tool is missing." >&2
          exit 1
        fi

        # Keep local CAs; this controls Alpine's trust store, not every Nix/Bun consumer.
        ${pkgs.gnused}/bin/sed -i \
          -e 's|^mozilla/emSign_ECC_Root_CA_-_G3[.]crt$|!&|' \
          -e 's|^mozilla/emSign_ECC_Root_CA_-_C3[.]crt$|!&|' \
          -e 's|^mozilla/emSign_Root_CA_-_C1[.]crt$|!&|' \
          -e 's|^mozilla/Comodo_AAA_Services_root[.]crt$|!&|' \
          /etc/ca-certificates.conf
        for certificate in \
          mozilla/emSign_ECC_Root_CA_-_G3.crt \
          mozilla/emSign_ECC_Root_CA_-_C3.crt \
          mozilla/emSign_Root_CA_-_C1.crt \
          mozilla/Comodo_AAA_Services_root.crt; do
          if ! ${pkgs.gnugrep}/bin/grep -Fxq "!$certificate" /etc/ca-certificates.conf; then
            printf '\n!%s\n' "$certificate" >> /etc/ca-certificates.conf
          fi
        done
        /usr/sbin/update-ca-certificates
      '';

  home.activation.configureAlpineRoot = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ! grep -qx '${pkgs.fish}/bin/fish' /etc/shells; then
      printf '%s\n' '${pkgs.fish}/bin/fish' >> /etc/shells
    fi
    /usr/sbin/usermod -s ${pkgs.fish}/bin/fish root
  '';

  home.activation.sopsAlpine =
    if config.sops.secrets == { } then
      lib.hm.dag.entryAfter [ "writeBoundary" ] ":"
    else
      lib.hm.dag.entryAfter [ "sops-nix" ] ''
        export XDG_RUNTIME_DIR=/run/user/0
        ${pkgs.coreutils}/bin/install -d -m 0700 "$XDG_RUNTIME_DIR"
        ${builtins.head config.systemd.user.services.sops-nix.Service.ExecStart}
      '';
}
