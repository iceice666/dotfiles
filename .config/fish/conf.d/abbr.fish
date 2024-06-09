function multicd
  echo cd (string repeat -n (math (string length -- $argv[1]) - 1 ) ../)
end

abbr --add dotdot --regex '^\.\.+$' --function multicd

abbr --add cdhome --regex '^home$' "cd $HOME"
abbr --add cdprev --regex '^-$' "cd $OLDOWD"
