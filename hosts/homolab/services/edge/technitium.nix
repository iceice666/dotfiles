{ homolab, pkgs, ... }:

let
  technitiumDnsServerLibraryNugetDeps = builtins.toFile "technitium-dns-server-library-v15-nuget-deps.json" ''
    [
      {
        "pname": "BouncyCastle.Cryptography",
        "version": "2.6.2",
        "hash": "sha256-Yjk2+x/RcVeccGOQOQcRKCiYzyx1mlFnhS5auCII+Ms="
      },
      {
        "pname": "Microsoft.Win32.SystemEvents",
        "version": "6.0.0",
        "hash": "sha256-N9EVZbl5w1VnMywGXyaVWzT9lh84iaJ3aD48hIBk1zA="
      },
      {
        "pname": "QRCoder",
        "version": "1.8.0",
        "hash": "sha256-UvOeFFxUZ/bddmDs6IamiYGDIfgxybE/CSpPyy5DMxI="
      },
      {
        "pname": "System.Drawing.Common",
        "version": "6.0.0",
        "hash": "sha256-/9EaAbEeOjELRSMZaImS1O8FmUe8j4WuFUw1VOrPyAo="
      }
    ]
  '';

  technitiumDnsServerNugetDeps = builtins.toFile "technitium-dns-server-v15-nuget-deps.json" ''
    [
      {
        "pname": "BouncyCastle.Cryptography",
        "version": "2.6.2",
        "hash": "sha256-Yjk2+x/RcVeccGOQOQcRKCiYzyx1mlFnhS5auCII+Ms="
      },
      {
        "pname": "Microsoft.AspNetCore.Authentication.OpenIdConnect",
        "version": "10.0.7",
        "hash": "sha256-hr1QgB9miQO2rXj5heibTX/fa3Tj/Nci8G/pDcrq11c="
      },
      {
        "pname": "Microsoft.IdentityModel.Abstractions",
        "version": "8.0.1",
        "hash": "sha256-zPWUKTCfGm4MWcYPU037NzezsFE1g8tEijjQkw5iooI="
      },
      {
        "pname": "Microsoft.IdentityModel.JsonWebTokens",
        "version": "8.0.1",
        "hash": "sha256-Xv9MUnjb66U3xeR9drOcSX5n2DjOCIJZPMNSKjWHo9Y="
      },
      {
        "pname": "Microsoft.IdentityModel.Logging",
        "version": "8.0.1",
        "hash": "sha256-FfwrH/2eLT521Kqw+RBIoVfzlTNyYMqlWP3z+T6Wy2Y="
      },
      {
        "pname": "Microsoft.IdentityModel.Protocols",
        "version": "8.0.1",
        "hash": "sha256-v3DIpG6yfIToZBpHOjtQHRo2BhXGDoE70EVs6kBtrRg="
      },
      {
        "pname": "Microsoft.IdentityModel.Protocols.OpenIdConnect",
        "version": "8.0.1",
        "hash": "sha256-ZHKaZxqESk+OU1SFTFGxvZ71zbdgWqv1L6ET9+fdXX0="
      },
      {
        "pname": "Microsoft.IdentityModel.Tokens",
        "version": "8.0.1",
        "hash": "sha256-beVbbVQy874HlXkTKarPTT5/r7XR1NGHA/50ywWp7YA="
      },
      {
        "pname": "Microsoft.Win32.SystemEvents",
        "version": "6.0.0",
        "hash": "sha256-N9EVZbl5w1VnMywGXyaVWzT9lh84iaJ3aD48hIBk1zA="
      },
      {
        "pname": "QRCoder",
        "version": "1.8.0",
        "hash": "sha256-UvOeFFxUZ/bddmDs6IamiYGDIfgxybE/CSpPyy5DMxI="
      },
      {
        "pname": "System.Drawing.Common",
        "version": "6.0.0",
        "hash": "sha256-/9EaAbEeOjELRSMZaImS1O8FmUe8j4WuFUw1VOrPyAo="
      },
      {
        "pname": "System.IdentityModel.Tokens.Jwt",
        "version": "8.0.1",
        "hash": "sha256-hW4f9zWs0afxPbcMqCA/FAGvBZbBFSkugIOurswomHg="
      }
    ]
  '';

  technitiumDnsServerLibrary = pkgs.callPackage (
    {
      lib,
      buildDotnetModule,
      fetchFromGitHub,
      dotnetCorePackages,
    }:
    buildDotnetModule rec {
      pname = "technitium-dns-server-library";
      version = "dns-server-v15.0.1";

      src = fetchFromGitHub {
        owner = "TechnitiumSoftware";
        repo = "TechnitiumLibrary";
        tag = version;
        hash = "sha256-NHEt6V3VdLRFVrWhTUwsWh9pas9e3tlxw2qJJTMrYec=";
        name = "${pname}-${version}";
      };

      dotnet-sdk = dotnetCorePackages.sdk_10_0;

      nugetDeps = technitiumDnsServerLibraryNugetDeps;

      projectFile = [
        "TechnitiumLibrary.ByteTree/TechnitiumLibrary.ByteTree.csproj"
        "TechnitiumLibrary.Net/TechnitiumLibrary.Net.csproj"
        "TechnitiumLibrary.Security.OTP/TechnitiumLibrary.Security.OTP.csproj"
      ];

      meta = {
        changelog = "https://github.com/TechnitiumSoftware/DnsServer/blob/master/CHANGELOG.md";
        description = "Library for Authorative and Recursive DNS server for Privacy and Security";
        homepage = "https://github.com/TechnitiumSoftware/DnsServer";
        license = lib.licenses.gpl3Only;
        mainProgram = "technitium-dns-server-library";
        maintainers = with lib.maintainers; [ fabianrig ];
        platforms = lib.platforms.linux;
      };
    }
  ) { };

  technitiumDnsServer =
    pkgs.callPackage
      (
        {
          lib,
          buildDotnetModule,
          fetchFromGitHub,
          dotnetCorePackages,
          technitium-dns-server-library,
          libmsquic,
        }:
        buildDotnetModule rec {
          pname = "technitium-dns-server";
          version = "15.0.1";

          src = fetchFromGitHub {
            owner = "TechnitiumSoftware";
            repo = "DnsServer";
            tag = "v${version}";
            hash = "sha256-U6Hpg2HMd8o+vXuu4XQo2P5sZDyQ5jPiU3+oPw/rsPs=";
            name = "${pname}-${version}";
          };

          dotnet-sdk = dotnetCorePackages.sdk_10_0;
          dotnet-runtime = dotnetCorePackages.aspnetcore_10_0;

          nugetDeps = technitiumDnsServerNugetDeps;

          projectFile = [ "DnsServerApp/DnsServerApp.csproj" ];

          preBuild = ''
            mkdir -p ../TechnitiumLibrary/bin
            cp -r ${technitium-dns-server-library}/lib/${technitium-dns-server-library.pname}/* ../TechnitiumLibrary/bin/
          '';

          postFixup = ''
            mv $out/bin/DnsServerApp $out/bin/technitium-dns-server
          '';

          runtimeDeps = [ libmsquic ];

          meta = {
            changelog = "https://github.com/TechnitiumSoftware/DnsServer/blob/master/CHANGELOG.md";
            description = "Authorative and Recursive DNS server for Privacy and Security";
            homepage = "https://github.com/TechnitiumSoftware/DnsServer";
            license = lib.licenses.gpl3Only;
            mainProgram = "technitium-dns-server";
            maintainers = with lib.maintainers; [ fabianrig ];
            platforms = lib.platforms.linux;
          };
        }
      )
      {
        technitium-dns-server-library = technitiumDnsServerLibrary;
      };
in

{
  services.technitium-dns-server = {
    enable = true;
    package = technitiumDnsServer;
  };

  # Technitium reads these initialization settings only for a fresh state dir.
  systemd.services.technitium-dns-server.environment = {
    DNS_SERVER_DOMAIN = homolab.domains.home;
    DNS_SERVER_WEB_SERVICE_LOCAL_ADDRESSES = "127.0.0.1";
    DNS_SERVER_WEB_SERVICE_HTTP_PORT = toString homolab.ports.technitium;
    DNS_SERVER_OPTIONAL_PROTOCOL_DNS_OVER_HTTP = "true";
    DNS_SERVER_LOG_USING_LOCAL_TIME = "true";
  };
}
