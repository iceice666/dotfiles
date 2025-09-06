# Completions for clone function
complete -c clone -f -n "__fish_is_first_token" -a "Projects Work Experiments" -d "Base directory"
complete -c clone -f -n "__fish_is_nth_token 2" -d "GitHub repository (user/repo)"