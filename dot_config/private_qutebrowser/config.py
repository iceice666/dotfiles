import os
from urllib.request import urlopen


config.load_autoconfig()


# Setup bindings
config.unbind("ga")
config.unbind("th")
config.unbind("tl")

config.bind("te", "config-cycle tabs.show multiple never")
config.bind("td", "config-cycle colors.webpage.darkmode.enabled true false")
config.bind("h", "history -t")
config.bind("gh", "back -t")
config.bind("gl", "forawrd -t")
config.bind("<Ctrl-Shift-p>", "spawn --userscript qute-bitwarden")
## Watch videos with mpv
config.bind(",m", "spawn --userscript umpv {url}")
config.bind(",M", "hint links spawn --userscript umpv {hint-url}")
config.bind(";M", "hint --rapid links spawn --userscript umpv {hint-url}")


c.auto_save.session = True
c.content.autoplay = False

c.content.headers.user_agent = "https://accounts.google.com/*:Mozilla/5.0 ({os_info}; rv:90.0) Gecko/20100101 Firefox/90.0"


# Privacy
c.content.canvas_reading = False
c.content.webgl = False
c.content.webrtc_ip_handling_policy = "default-public-interface-only"
# Adblocking
c.content.blocking.enabled = True
c.content.blocking.method = "both"
c.content.blocking.adblock.lists = [
    "https://ublockorigin.github.io/uAssets/filters/quick-fixes.min.txt",
    "https://ublockorigin.github.io/uAssets/filters/unbreak.min.txt",
    "https://ublockorigin.github.io/uAssets/filters/filters.min.txt",
    "https://ublockorigin.github.io/uAssets/filters/privacy.min.txt",
    "https://ublockorigin.github.io/uAssets/filters/ubol-filters.txt",
    "https://ublockorigin.github.io/uAssets/filters/badware.min.txt",
    "https://ublockorigin.github.io/uAssets/filters/filters-mobile.txt",
    "https://ublockorigin.github.io/uAssets/filters/annoyances-others.txt",
    "https://ublockorigin.github.io/uAssets/filters/lan-block.txt",
    "https://ublockorigin.github.io/uAssets/filters/annoyances-cookies.txt",
    "https://ublockorigin.github.io/uAssets/thirdparties/easylist.txt",
    "https://ublockorigin.github.io/uAssets/thirdparties/easylist-cookies.txt",
    "https://ublockorigin.github.io/uAssets/thirdparties/easylist-newsletters.txt",
    "https://ublockorigin.github.io/uAssets/thirdparties/easylist-social.txt",
    "https://ublockorigin.github.io/uAssets/thirdparties/easylist-chat.txt",
    "https://ublockorigin.github.io/uAssets/thirdparties/easylist-annoyances.txt",
    "https://ublockorigin.github.io/uAssets/thirdparties/easylist-notifications.txt",
    "https://ublockorigin.github.io/uAssets/thirdparties/easyprivacy.txt",
    "https://filters.adtidy.org/extension/ublock/filters/11.txt",
    "https://filters.adtidy.org/extension/ublock/filters/17.txt",
    "https://filters.adtidy.org/extension/ublock/filters/224.txt",
    "https://someonewhocares.org/hosts/hosts",
    "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=1&mimetype=plaintext",
    "https://malware-filter.gitlab.io/malware-filter/urlhaus-filter-hosts.txt",
    "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts",
]

# Search settings
c.url.searchengines = {
    "DEFAULT": "https://duckduckgo.com/?q={}",
    "!apkg": "https://archlinux.org/packages/?q={}",
    "!aw": "https://wiki.archlinux.org/?search={}",
    "!aur": "https://aur.archlinux.org/packages?K={}",
    "!librs": "https://lib.rs/search?q={}",
    "!docrs": "https://docs.rs/releases/search?query={}",
    "!yt": "https://www.youtube.com/results?search_query={}",
    "!ytid": "https://www.youtube.com/watch?v={}",
    "!gh": "https://github.com/search?o=desc&s=stars&q={}",
}


# Fonts
c.fonts.default_family = "Terminess Nerd Font Propo"
c.fonts.default_size = "16pt"
c.fonts.statusbar = "default_size default_family"
c.fonts.tabs.selected = "12pt Noto Sans CJK TC"
c.fonts.tabs.unselected = "12pt Noto Sans CJK TC"

# Tabs
c.tabs.mousewheel_switching = False
c.tabs.position = "left"
c.tabs.select_on_remove = "last-used"
c.tabs.show = "multiple"
c.tabs.width = "20%"
c.tabs.title.elide = "right"

# Dark mode setup
c.colors.webpage.darkmode.policy.images = "never"
c.colors.webpage.darkmode.algorithm = "lightness-cielab"
config.set("colors.webpage.darkmode.enabled", False, "file://*")


# Setup theme
if not os.path.exists(config.configdir / "theme.py"):
    theme = "https://raw.githubusercontent.com/catppuccin/qutebrowser/main/setup.py"
    with urlopen(theme) as themehtml:
        with open(config.configdir / "theme.py", "a") as file:
            file.writelines(themehtml.read().decode("utf-8"))

if os.path.exists(config.configdir / "theme.py"):
    import theme

    theme.setup(c, "mocha", True)
