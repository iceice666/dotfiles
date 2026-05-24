{
  buildGoModule,
  fetchFromGitHub,
  lib,
}:

buildGoModule rec {
  pname = "ketch";
  version = "0.9.1";

  src = fetchFromGitHub {
    owner = "1broseidon";
    repo = "ketch";
    rev = "v${version}";
    hash = "sha256-oFgLV/p+5eoClCl5efjAdOyFw+HTtx2vI4aBgXvDK9A=";
  };

  vendorHash = "sha256-m3IwAYsczsxcVk9fay+f2AsNjmXoPk7NS0abES6b594=";

  ldflags = [
    "-s"
    "-w"
    "-X github.com/1broseidon/ketch/cmd.version=${version}"
  ];

  meta = {
    description = "Fast CLI for web search, code search, library docs, and scraping";
    homepage = "https://github.com/1broseidon/ketch";
    license = lib.licenses.mit;
    mainProgram = "ketch";
    platforms = lib.platforms.unix;
  };
}
