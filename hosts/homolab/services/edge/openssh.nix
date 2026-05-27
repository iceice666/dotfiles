{ username, ... }:

{
  services.openssh = {
    enable = true;
    ports = [ 2222 ];
    settings = {
      PermitRootLogin = "no";
      AllowUsers = [ username ];
      PasswordAuthentication = false;
    };
  };
}
