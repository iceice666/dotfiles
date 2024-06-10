function multicd
  echo cd (string repeat -n (math (string length -- $argv[1]) - 1 ) ../)
end

abbr --add dotdot --regex '^\.\.+$' --function multicd

abbr --add cdhome --regex '^home$' "cd $HOME"


abbr --add rm rm -r
abbr --add cp cp -r
abbr --add mkdir mkdir -p

if test -e /etc/arch-release
  if type -q paru 
    set -l pkg paru
  else if type -q yay
    set -l pkg yay
  else if type pacman
    set -l pkg pacman
  else 
    echo Which package manager do you use?
  end

  # I dont know why $pkg contains extra space
  abbr --add pm pm "$pkg"
  abbr --add pms pms "$pkg-S"
  abbr --add pmr pmr "$pkg-R"
  abbr --add pmu pmu "$pkg-Syu"
  abbr --add pmq pmq "$pkg-Q | rg"
end
