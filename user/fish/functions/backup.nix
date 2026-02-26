{ ... }:

{
  programs.fish.functions.backup = {
    description = "Create timestamped backup of file or directory";
    body = ''
      if test (count $argv) -eq 0
          echo "Usage: backup <file-or-directory>"
          return 1
      end

      set -l target $argv[1]

      if not test -e $target
          echo "File or directory not found: $target"
          return 1
      end

      set -l timestamp (date +"%Y%m%d_%H%M%S")
      set -l backup_name "$target.backup_$timestamp"

      if test -d $target
          cp -r $target $backup_name
          echo "Directory backed up to: $backup_name"
      else
          cp $target $backup_name
          echo "File backed up to: $backup_name"
      end
    '';
  };
}
