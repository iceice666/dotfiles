{
  pkgs,
  dotfiles,
  ...
}:

let
  desktopWallpaper = dotfiles + /assets/m3air-desktop.png;

  applyWallpaper = pkgs.writeShellScript "m3air-apply-wallpaper" ''
    #!/usr/bin/env bash
    set -euo pipefail

    desktop_wallpaper='${desktopWallpaper}'
    wallpaper_store="$HOME/Library/Application Support/com.apple.wallpaper/Store/Index.plist"

    if [ ! -f "$desktop_wallpaper" ]; then
      echo "missing desktop wallpaper: $desktop_wallpaper" >&2
      exit 1
    fi

    if [ ! -f "$wallpaper_store" ]; then
      echo "wallpaper store not found: $wallpaper_store" >&2
      exit 1
    fi

    ${pkgs.python3}/bin/python3 <<'PY'
    import datetime as dt
    import os
    import plistlib
    import tempfile

    desktop_wallpaper = "${desktopWallpaper}"
    wallpaper_store = os.path.expanduser("~/Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    now = dt.datetime.now()

    def image_configuration(path):
      return plistlib.dumps(
        {
          "type": "imageFile",
          "url": {"relative": f"file://{path}"},
        },
        fmt=plistlib.FMT_BINARY,
        sort_keys=False,
      )

    def update_choice(choice, path):
      choice["Provider"] = "com.apple.wallpaper.choice.image"
      choice["Configuration"] = image_configuration(path)

      files = choice.get("Files")
      if isinstance(files, list) and files:
        first = files[0]
        if isinstance(first, dict):
          first["relative"] = f"file://{path}"

    def update_linked_entry(entry, path):
      if not isinstance(entry, dict) or entry.get("Type") != "linked":
        return False

      linked = entry.get("Linked")
      if not isinstance(linked, dict):
        return False

      content = linked.get("Content")
      if not isinstance(content, dict):
        return False

      choices = content.get("Choices")
      if not isinstance(choices, list) or not choices:
        return False

      first = choices[0]
      if not isinstance(first, dict):
        return False

      update_choice(first, path)
      linked["LastSet"] = now
      linked["LastUse"] = now
      return True

    with open(wallpaper_store, "rb") as f:
      data = plistlib.load(f)

    updated = False

    updated = update_linked_entry(data.get("AllSpacesAndDisplays"), desktop_wallpaper) or updated
    updated = update_linked_entry(data.get("SystemDefault"), desktop_wallpaper) or updated

    if not updated:
      raise RuntimeError("unable to locate Tahoe wallpaper linked entries in Index.plist")

    fd, temp_path = tempfile.mkstemp(dir=os.path.dirname(wallpaper_store))
    os.close(fd)
    try:
      with open(temp_path, "wb") as f:
        plistlib.dump(data, f, fmt=plistlib.FMT_BINARY, sort_keys=False)
      os.replace(temp_path, wallpaper_store)
    finally:
      if os.path.exists(temp_path):
        os.unlink(temp_path)
    PY

    /usr/bin/killall WallpaperAgent || true
  '';
in
{
  launchd.agents.wallpaper-refresh = {
    enable = true;
    config = {
      Label = "com.iceice666.wallpaper-refresh";
      ProgramArguments = [ "${applyWallpaper}" ];
      RunAtLoad = true;

      StandardOutPath = "/tmp/com.iceice666.wallpaper-refresh.log";
      StandardErrorPath = "/tmp/com.iceice666.wallpaper-refresh.err";
    };
  };
}
