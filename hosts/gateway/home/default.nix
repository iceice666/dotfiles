{ dotfiles, ... }:

{
  imports = [
    (dotfiles + /common/home-alpine)
    ./services
  ];
}
