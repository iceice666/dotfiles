{ ... }:

{
  programs.fish.functions.nuke = {
    description = "Remove files or directories with guardrails";
    body = ''
      set -l force 0
      set -l dry_run 0
      set -l raw_targets

      for arg in $argv
          switch $arg
              case -f --force
                  set force 1
              case -n --dry-run
                  set dry_run 1
              case -h --help
                  echo "Usage: nuke [--force] [--dry-run] [PATH ...]"
                  echo "       nuke"
                  echo
                  echo "Without PATH, nuke removes the current directory."
                  return 0
              case '*'
                  set -a raw_targets $arg
          end
      end

      if test (count $raw_targets) -eq 0
          set raw_targets .
      end

      set -l targets
      set -l delete_cwd 0
      set -l cwd (pwd -P)

      for raw_target in $raw_targets
          if not test -e $raw_target
              echo "Path not found: $raw_target"
              return 1
          end

          set -l target (realpath $raw_target)
          if test $status -ne 0
              echo "Failed to resolve path: $raw_target"
              return 1
          end

          switch $target
              case /
                  echo "Refusing to nuke /."
                  return 1
              case $HOME
                  echo "Refusing to nuke $HOME."
                  return 1
          end

          if contains -- $target $targets
              continue
          end

          if test "$target" = "$cwd"
              set delete_cwd 1
          end

          set -a targets $target
      end

      if test (count $targets) -eq 0
          echo "Nothing to nuke."
          return 1
      end

      if test $dry_run -eq 1
          echo "Would nuke:"
          for target in $targets
              echo "  $target"
          end
          return 0
      end

      if test $force -ne 1
          echo "About to nuke:"
          for target in $targets
              echo "  $target"
          end

          read -l -P "Continue? [y/N] " confirm
          if not string match -qi 'y' -- $confirm
              echo "Aborted."
              return 1
          end
      end

      if test $delete_cwd -eq 1
          set -l parent (dirname $cwd)
          cd $parent
          or begin
              echo "Failed to move to $parent before deleting $cwd"
              return 1
          end
      end

      rm -rf $targets
      or begin
          echo "Failed to nuke target(s)."
          return 1
      end

      for target in $targets
          echo "Nuked $target"
      end

      if test $delete_cwd -eq 1
          echo "Moved to $parent"
      end
    '';
  };
}
