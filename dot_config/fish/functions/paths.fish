function paths --description "Print \$PATH"
    echo $PATH | tr ' ' '\n' | sort
end
