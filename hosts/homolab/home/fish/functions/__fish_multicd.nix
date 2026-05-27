{ ... }:

{
  programs.fish.functions.__fish_multicd = {
    description = "Convert repeated dots to cd ../..";
    body = "echo cd (string repeat -n (math (string length -- $argv[1]) - 1 ) ../)";
  };
}
