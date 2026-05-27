{ ... }:

{
  programs.fish.functions.mcd = {
    description = "Make directory and change into it";
    body = ''
      if test (count $argv) -ne 1
          echo "Usage: mcd <directory>"
          return 1
      end

      if not mkdir -p $argv[1]
          echo "Failed to create directory: $argv[1]"
          return 1
      end

      cd $argv[1]
    '';
  };
}
