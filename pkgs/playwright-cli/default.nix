{ lib, buildNpmPackage }:

buildNpmPackage {
  pname = "playwright-cli";
  version = "0.1.20";
  src = ./.;
  npmDepsHash = "sha256-Ilwi6EemjzdOtva7sX0BMCrA3gy+g0jq0tzFPaJdU0I=";
  dontNpmBuild = true;
  npmFlags = [ "--ignore-scripts" ];
  PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
  NO_UPDATE_NOTIFIER = "1";

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    node --test tests/*.test.cjs
    node cli.cjs --version
    runHook postCheck
  '';

  meta = {
    description = "Pinned Playwright CLI with rendered-page Markdown extraction";
    homepage = "https://github.com/microsoft/playwright-cli";
    license = lib.licenses.asl20;
    mainProgram = "playwright-cli";
    platforms = [
      "aarch64-darwin"
      "x86_64-linux"
    ];
  };
}
