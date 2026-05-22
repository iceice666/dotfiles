{
  buildGoModule,
  fetchFromGitHub,
  lib,
}:

buildGoModule rec {
  pname = "ketch";
  version = "0.9.0";

  src = fetchFromGitHub {
    owner = "1broseidon";
    repo = "ketch";
    rev = "v${version}";
    hash = "sha256-IWmlNd7Fy47Wc4vyc0XjkqCHvGR7SdOIQl4oyDgIU54=";
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
