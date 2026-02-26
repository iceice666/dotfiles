{ ... }:

{
  programs.fish.functions.print_dog = {
    description = "Summon a dog (currently unavailable)";
    body = ''
      echo "🐕 Woof! Dog feature coming s∞n™..."
      echo ""
      echo "      /^   ^\\"
      echo "     (  ._. )    meow"
      echo "      o_(\")(\") "
    '';
  };
}
