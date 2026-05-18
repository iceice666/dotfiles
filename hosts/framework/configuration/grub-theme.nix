{ pkgs, ... }:

let
  font = "${pkgs.liberation_ttf}/share/fonts/truetype/LiberationSans-Regular.ttf";
  fontBold = "${pkgs.liberation_ttf}/share/fonts/truetype/LiberationSans-Bold.ttf";
  rickrollUrl = "https://www.youtube.com/watch?v=dQw4w9WgXcQ";

  themeText = pkgs.writeText "grub-bsod-meme-theme.txt" ''
    title-text: ""
    title-font: "Liberation Sans Bold 28"
    message-font: "Liberation Sans Regular 18"
    message-color: "#ffffff"
    message-bg-color: "#0078d7"
    desktop-color: "#0078d7"

    + label {
        top = 8%
        left = 7%
        width = 86%
        text = ":)"
        font = "Liberation Sans Regular 86"
        color = "#ffffff"
    }

    + label {
        top = 27%
        left = 7%
        width = 86%
        text = "Great! You're computer is fine."
        font = "Liberation Sans Bold 28"
        color = "#ffffff"
    }

    + label {
        top = 34%
        left = 7%
        width = 86%
        text = "Choose ur options below fr"
        font = "Liberation Sans Regular 22"
        color = "#ffffff"
    }

    + label {
        top = 43%
        left = 7%
        width = 640
        text = "Pick ur boot sauce"
        font = "Liberation Sans Regular 18"
        color = "#ffffff"
    }

    + boot_menu {
        top = 48%
        left = 7%
        width = 660
        height = 196
        icon_width = 0
        icon_height = 0
        item_height = 32
        item_padding = 2
        item_icon_space = 0
        item_spacing = 4
        item_font = "Liberation Sans Regular 18"
        item_color = "#eaf6ff"
        selected_item_font = "Liberation Sans Bold 18"
        selected_item_color = "#ffffff"
    }

    + label {
        top = 100%-136
        left = 7%
        width = 660
        text = "If u call support, give them this vibe check code: 0x000000_OK"
        font = "Liberation Sans Regular 16"
        color = "#d8efff"
    }

    + image {
        top = 100%-206
        left = 100%-222
        file = "recovery-code.png"
    }

    + label {
        top = 100%-52
        left = 100%-280
        width = 240
        align = "center"
        text = "Scan 4K recovery code"
        font = "Liberation Sans Regular 16"
        color = "#ffffff"
    }
  '';

  bsodTheme =
    pkgs.runCommandLocal "grub-bsod-meme-theme" { nativeBuildInputs = [ pkgs.qrencode ]; }
      ''
        mkdir -p "$out"

        ${pkgs.grub2}/bin/grub-mkfont --size 16 --output "$out/liberation-regular-16.pf2" ${font}
        ${pkgs.grub2}/bin/grub-mkfont --size 18 --output "$out/liberation-regular-18.pf2" ${font}
        ${pkgs.grub2}/bin/grub-mkfont --size 18 --output "$out/liberation-bold-18.pf2" ${fontBold}
        ${pkgs.grub2}/bin/grub-mkfont --size 22 --output "$out/liberation-regular-22.pf2" ${font}
        ${pkgs.grub2}/bin/grub-mkfont --size 28 --output "$out/liberation-bold-28.pf2" ${fontBold}
        ${pkgs.grub2}/bin/grub-mkfont --size 86 --output "$out/liberation-regular-86.pf2" ${font}

        qrencode \
          --output "$out/recovery-code.png" \
          --size 6 \
          --margin 2 \
          ${pkgs.lib.escapeShellArg rickrollUrl}

        cp ${themeText} "$out/theme.txt"
      '';
in
{
  boot.loader.grub.theme = bsodTheme;
}
