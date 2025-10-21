function __fish_multicd
  echo cd (string repeat -n (math (string length -- $argv[1]) - 1 ) ../)
end

abbr --add dotdot --regex '^\.\.+$' --function __fish_multicd

abbr --add rm rm -r
abbr --add cp cp -r
abbr --add mkdir mkdir -p

abbr --add /reload "source ~/.config/fish/config.fish"
abbr --add /h "history"
abbr --add /c "clear"
