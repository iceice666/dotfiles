{pkgs, ...}:{
  # System packges

  environment.systemPackages = [
     pkgs.rust-bin.stable.latest.default
   ];
}
