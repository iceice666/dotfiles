{
  pkgs,
  username,
  homeDirectory,
  ...
}:

{
  imports = [
    ./edge.nix
  ];

  sops = {
    defaultSopsFormat = "yaml";

    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = false;
    };
  };

  # The home-manager sops user service has no SSH key and no native age
  # identity of its own, so mirror the system age key into a user-owned file it
  # can read. Group membership would force a re-login before the live user
  # systemd session could read a group-readable key, breaking deploy-rs
  # activation; a root-written copy avoids that.
  system.activationScripts.iceice666SopsAgeKey.text = ''
    ${pkgs.coreutils}/bin/install -d -m 0700 -o ${username} -g users \
      ${homeDirectory}/.config/sops/age
    ${pkgs.coreutils}/bin/install -m 0600 -o ${username} -g users \
      /var/lib/sops-nix/key.txt ${homeDirectory}/.config/sops/age/keys.txt
  '';

}
