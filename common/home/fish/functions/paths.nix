{ ... }:

{
  programs.fish.functions.paths = {
    description = "Print \$PATH";
    body = "echo $PATH | tr ' ' '\\n' | sort";
  };
}
