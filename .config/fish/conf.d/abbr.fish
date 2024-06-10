function multicd
  echo cd (string repeat -n (math (string length -- $argv[1]) - 1 ) ../)
end

abbr --add dotdot --regex '^\.\.+$' --function multicd

abbr --add cdhome --regex '^home$' "cd $HOME"
abbr --add cdprev --regex '^-$' "cd $OLDOWD"


abbr --add rm rm -r
abbr --add cp cp -r
abbr --add mkdir mkdir -p


function package_manager
  if type -q paru 
    echo "Paru found"
  end


end
