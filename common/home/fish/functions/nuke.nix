{ ... }:

{
  programs.fish.functions.nuke = {
    description = "Remove file or directory with confirmation";
    body = ''
      if test (count $argv) -eq 0
          set -l target (realpath .)
          set -l parent (dirname $target)
          read -l -P "Are you sure to nuke $target? [y/N] " confirm
          if string match -qi 'y' -- $confirm
              cd $parent
              rm -rf $target
              echo "Nuked $target and moved to $parent"
          else
              echo "Aborted."
          end
      else
          set -l target (realpath $argv[1])
          read -l -P "Are you sure to nuke $target? [y/N] " confirm
          if string match -qi 'y' -- $confirm
              rm -rf $target
          else
              echo "Aborted."
          end
      end
    '';
  };
}
