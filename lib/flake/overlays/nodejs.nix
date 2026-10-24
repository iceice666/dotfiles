{ }:

final: prev:
let
  nodejsSource = prev.path + "/pkgs/development/web/nodejs";
  runtime =
    major:
    final.callPackage ../../../pkgs/nodejs-bin {
      inherit major nodejsSource;
      cacert = final.dotfiles-cacert;
    };
  withTests =
    major: package:
    package.overrideAttrs (old: {
      passthru = old.passthru // {
        tests.nativeAddon = final.callPackage ../../../pkgs/nodejs-bin/native-addon-test.nix {
          nodejs = final."nodejs_${major}";
        };
      };
    });
in
{
  # Official fixed binaries avoid compiling V8 on the Raspberry Pi.
  nodejs-slim_22 = runtime "22";
  nodejs-slim_24 = runtime "24";
  nodejs_22 = withTests "22" (
    final.callPackage (nodejsSource + "/symlink.nix") {
      nodejs-slim = final.nodejs-slim_22;
    }
  );
  nodejs_24 = withTests "24" (
    final.callPackage (nodejsSource + "/symlink.nix") {
      nodejs-slim = final.nodejs-slim_24;
    }
  );
  nodejs = final.nodejs_24;
  nodejs-slim = final.nodejs-slim_24;
}
