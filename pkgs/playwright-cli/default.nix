{ lib, buildNpmPackage }:

buildNpmPackage {
  pname = "playwright-cli";
  version = "0.1.22";
  src = ./.;
  npmDepsHash = "sha256-4ii5LxSobA4cBpjwpoLYdZ8/weGYS2WnZJBgjL47lhA=";
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
