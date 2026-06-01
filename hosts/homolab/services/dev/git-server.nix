{ homolab, pkgs, ... }:

let
  gitHome = "/var/lib/git";
  repoRoot = "/srv/git";

  gitInitBare = pkgs.writeShellApplication {
    name = "homolab-git-init-bare";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.git-lfs
      pkgs.sudo
    ];
    text = ''
      if [ "$#" -ne 1 ]; then
        printf 'usage: homolab-git-init-bare <name.git>\n' >&2
        exit 2
      fi

      repo_name="$1"
      case "$repo_name" in
        /* | *..* | *//* | *.git)
          ;;
        *)
          repo_name="$repo_name.git"
          ;;
      esac

      case "$repo_name" in
        /* | *..* | *//*)
          printf 'invalid repository name: %s\n' "$repo_name" >&2
          exit 2
          ;;
      esac

      repo_path="${repoRoot}/$repo_name"
      if [ -e "$repo_path" ]; then
        printf 'repository already exists: %s\n' "$repo_path" >&2
        exit 1
      fi

      sudo -u git -- git init --bare "$repo_path"
      sudo -u git -- git -C "$repo_path" lfs install --local
      printf 'created %s\n' "$repo_path"
      printf 'remote: ssh://git@homolab:%s%s\n' '${toString homolab.ports.ssh}' "$repo_path"
    '';
  };
in
{
  users = {
    groups.git = { };

    users.git = {
      isSystemUser = true;
      group = "git";
      home = gitHome;
      createHome = true;
      shell = "${pkgs.git}/bin/git-shell";
    };
  };

  environment.systemPackages = [
    gitInitBare
    pkgs.git
    pkgs.git-lfs
    pkgs.git-lfs-transfer
  ];

  systemd.tmpfiles.rules = [
    "d ${repoRoot} 0750 git git - -"
    "d ${gitHome} 0750 git git - -"
    "d ${gitHome}/.ssh 0700 git git - -"
    "f ${gitHome}/.ssh/authorized_keys 0600 git git - -"
    "d ${gitHome}/git-shell-commands 0755 git git - -"
    "L+ ${gitHome}/git-shell-commands/git-lfs-transfer - - - - ${pkgs.git-lfs-transfer}/bin/git-lfs-transfer"
  ];
}
