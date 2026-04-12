{ ... }:

{
  programs.fish.functions.pj = {
    description = "Jump to project directory";
    body = ''
      if not test -d $ProjectDir
          echo "Project directory not found: $ProjectDir"
          return 1
      end

      if not type -q fzf
          echo "fzf is required for pj"
          return 1
      end

      set query (string join ' ' -- $argv)
      set target (
          for d in $ProjectDir/*
              if test -d $d
                  basename $d
              end
          end | fzf --query "$query"
      )

      if test -z "$target"
          return 1
      end

      set target $ProjectDir/$target
      cd $target
    '';
  };
}
