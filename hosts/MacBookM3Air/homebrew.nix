{...}: {
  # Managing package which doesn't included in home-manager on MacOS with homebrew

  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = true;
      upgrade = true;
      # 'zap': uninstalls all formulae(and related files) not listed here.
      cleanup = "zap";
    };

    taps = [
      "homebrew/services"
    ];

    # `brew install`
    # Feel free to add your favorite apps here.
    brews = [
      "pipx"
    ];

    # `brew install --cask`
    # Feel free to add your favorite apps here.
    casks = [
      # chatting
      "slack"
      "discord"

      # small tools, utilities
      "snipaste"
      "jordanbaird-ice"
      "stats"

      # others
      "orbstack"
      "obs"
    ];
  };
}
