# Fish Shell Configuration


# Environment Variables
set -gx EDITOR nvim
set -gx ProjectDir ~/Project
set -gx BUN_INSTALL $HOME/.bun
set -gx HOSTNAME (hostname)


# PATH setup
fish_add_path -p ~/go/bin
fish_add_path -p $BUN_INSTALL/bin
fish_add_path -p ~/.cargo/bin
fish_add_path -p ~/.local/bin
fish_add_path -p ~/bin

# Better directory colors for ls/eza
if type -q dircolors
    eval (dircolors -c ~/.dircolors 2>/dev/null; or dircolors -c)
end

# Enable vi key bindings (uncomment if preferred)
# fish_vi_key_bindings

# Set up fzf integration if available
if type -q fzf
    set -gx FZF_DEFAULT_OPTS '--height 40% --layout=reverse --border'
end


# Shell appearance and behavior
set -g fish_greeting ""  # Disable greeting message

# Initialize starship prompt
starship init fish | source
