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

  # Overlay-free Node for packages that use it only while building or testing.
  # prev.nodejs is not enough: it still resolves the pinned slim runtime through
  # the fixpoint. Keeping these consumers on upstream Node keeps them on the
  # binary cache instead of compiling Chromium, rebuilding most Python
  # environments, or hitting flaky test suites.
  upstreamPkgs = import prev.path {
    localSystem = prev.stdenv.buildPlatform;
    crossSystem = prev.stdenv.hostPlatform;
    inherit (prev) config;
  };
  buildOnlyNodejs = upstreamPkgs.nodejs;

  # overrideScope drops .override, which python-packages uses on qt6.
  qtScope =
    scope:
    scope.overrideScope (
      _: qtPrev: {
        qtwebengine = qtPrev.qtwebengine.override { nodejs = buildOnlyNodejs; };
      }
    )
    // {
      override = args: qtScope (scope.override args);
    };
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

  # Build/test-only Node consumers. Runtime consumers (e.g. zed-editor) keep the
  # pinned runtime and build locally.
  # Only nixpkgs-unstable's libmysofa takes nodejs (for its tests).
  libmysofa =
    if prev.libmysofa.override.__functionArgs ? nodejs then
      prev.libmysofa.override { nodejs = buildOnlyNodejs; }
    else
      prev.libmysofa;
  neovim-unwrapped = prev.neovim-unwrapped.override { nodejs = buildOnlyNodejs; };
  qt6 = qtScope prev.qt6;
  # furo's npm-built web assets reach most Python environments via tox.
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (_: pyPrev: {
      furo = pyPrev.furo.override {
        nodejs = buildOnlyNodejs;
        inherit (upstreamPkgs) buildNpmPackage;
      };
    })
  ];
}
