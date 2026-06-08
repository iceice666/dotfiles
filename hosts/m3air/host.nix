{ ... }:

{
  name = "m3air";
  kind = "darwin";
  system = "aarch64-darwin";
  username = "iceice666";
  homeDirectory = "/Users/iceice666";

  modules = [ ./configuration ];

  features = {
    homeManager = true;
    sops = true;
  };
}
