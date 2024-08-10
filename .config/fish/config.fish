set -U EDITOR nvim
set -U PROJECT_PATHS ~/project
set -a fish_function_path $HOME/.config/fish/functions/custom

if status is-interactive
    # Commands to run in interactive sessions can go here
end

starship init fish | source
