


################# executors #####################


function __mgr_arch
  if not string length -q -- $argv[1]
    return 1
  end

  set -l mgr $argv[1]

  abbr --add pm "$mgr"
  abbr --add pms "$mgr -S"
  abbr --add pmr "$mgr -R"
  abbr --add pmu "$mgr -Syu"
  abbr --add pmq "$mgr -Q | rg"

end




################# dispatcher #####################

if test -e /etc/arch-release
  if type -q paru 
    __mgr_arch paru
  else if type -q yay
    __mgr_arch yay
  else if type pacman
    __mgr_arch pacman
  end

end
