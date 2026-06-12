{
  lib,
  pkgs,
  ...
}:

let
  gitHome = "/var/lib/git";
  repoRoot = "/srv/git";

  gitInitBare = pkgs.writeShellApplication {
    name = "homolab-git-init-bare";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.git-lfs
      pkgs.util-linux
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

      runuser -u git -- ${pkgs.git}/bin/git init --bare "$repo_path"
      runuser -u git -- ${pkgs.git}/bin/git -C "$repo_path" lfs install --local
      printf 'created %s\n' "$repo_path"
      printf 'remote: ssh://git@lumo:22%s\n' "$repo_path"
    '';
  };
in
{
  home.packages = [
    gitInitBare
    pkgs.git
    pkgs.git-lfs
    pkgs.git-lfs-transfer
  ];

  home.activation.lumoGitServer = lib.hm.dag.entryAfter [ "lumoDirectories" ] ''
    if ! /usr/bin/getent group git >/dev/null; then
      /usr/sbin/addgroup -S git
    fi
    if ! /usr/bin/id git >/dev/null 2>&1; then
      /usr/sbin/adduser -S -D -H -h ${gitHome} -s ${pkgs.git}/bin/git-shell -G git git
    else
      /usr/sbin/usermod -d ${gitHome} -s ${pkgs.git}/bin/git-shell git
    fi

    install -d -m 0750 -o git -g git ${repoRoot} ${gitHome}
    install -d -m 0700 -o git -g git ${gitHome}/.ssh
    touch ${gitHome}/.ssh/authorized_keys
    chown git:git ${gitHome}/.ssh/authorized_keys
    chmod 0600 ${gitHome}/.ssh/authorized_keys
    install -d -m 0755 -o git -g git ${gitHome}/git-shell-commands
    ln -sfn ${pkgs.git-lfs-transfer}/bin/git-lfs-transfer \
      ${gitHome}/git-shell-commands/git-lfs-transfer
  '';
}
