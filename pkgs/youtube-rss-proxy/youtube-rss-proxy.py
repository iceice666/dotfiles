#!/usr/bin/env python3
import argparse
import json
import os
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

FEED_URL = "https://www.youtube.com/feeds/videos.xml"
NAMESPACES = {
    "atom": "http://www.w3.org/2005/Atom",
    "yt": "http://www.youtube.com/xml/schemas/2015",
}
MAX_DISPLAY_TITLE_LENGTH = 58


def parse_csv(value):
    return [entry.strip() for entry in value.split(",") if entry.strip()]


def parse_iso8601(value):
    if not value:
        return datetime.fromtimestamp(0, tz=timezone.utc)

    normalized = value.replace("Z", "+00:00")
    return datetime.fromisoformat(normalized)


def truncate_text(value, max_length=MAX_DISPLAY_TITLE_LENGTH):
    if len(value) <= max_length:
        return value

    if max_length <= 1:
        return value[:max_length]

    return "{}…".format(value[: max_length - 1].rstrip())


def fetch_feed(kind, value, timeout):
    query = urllib.parse.urlencode({kind: value})
    url = "{}?{}".format(FEED_URL, query)

    with urllib.request.urlopen(url, timeout=timeout) as response:
        payload = response.read()

    root = ET.fromstring(payload)
    videos = []

    for entry in root.findall("atom:entry", NAMESPACES):
        title = entry.findtext("atom:title", default="", namespaces=NAMESPACES)
        published = entry.findtext("atom:published", default="", namespaces=NAMESPACES)
        channel = entry.findtext(
            "atom:author/atom:name", default="", namespaces=NAMESPACES
        )
        video_id = entry.findtext("yt:videoId", default="", namespaces=NAMESPACES)
        url = (
            "https://www.youtube.com/watch?v={}".format(video_id)
            if video_id
            else "https://www.youtube.com"
        )

        display_title = truncate_text(
            "{} | {}".format(channel, title) if channel else title
        )

        videos.append(
            {
                "title": title,
                "displayTitle": display_title,
                "published": published,
                "channel": channel,
                "url": url,
                "publishedEpoch": int(parse_iso8601(published).timestamp()),
            }
        )

    return videos


class Handler(BaseHTTPRequestHandler):
    default_channels = []
    default_playlists = []
    timeout_seconds = 10
    max_limit = 25

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)

        if parsed.path == "/healthz":
            self.respond({"ok": True, "service": "youtube-rss-proxy"})
            return

        if parsed.path != "/videos":
            self.respond({"error": "not found"}, status=404)
            return

        query = urllib.parse.parse_qs(parsed.query)
        channels = parse_csv(query.get("channels", [""])[0]) or self.default_channels
        playlists = parse_csv(query.get("playlists", [""])[0]) or self.default_playlists

        requested_limit = query.get("limit", ["10"])[0]
        try:
            limit = max(1, min(int(requested_limit), self.max_limit))
        except ValueError:
            limit = 10

        videos = []
        errors = []

        for channel_id in channels:
            try:
                videos.extend(
                    fetch_feed("channel_id", channel_id, self.timeout_seconds)
                )
            except Exception as exc:
                errors.append("channel_id={}: {}".format(channel_id, exc))

        for playlist_id in playlists:
            try:
                videos.extend(
                    fetch_feed("playlist_id", playlist_id, self.timeout_seconds)
                )
            except Exception as exc:
                errors.append("playlist_id={}: {}".format(playlist_id, exc))

        videos.sort(key=lambda item: item.get("publishedEpoch", 0), reverse=True)

        deduped = []
        seen = set()
        for video in videos:
            key = video.get("url", "")
            if key in seen:
                continue

            seen.add(key)
            video.pop("publishedEpoch", None)
            deduped.append(video)
            if len(deduped) >= limit:
                break

        self.respond(
            {
                "videos": deduped,
                "channels": channels,
                "playlists": playlists,
                "errors": errors,
                "configured": bool(channels or playlists),
                "fetchedAt": datetime.now(tz=timezone.utc).isoformat(),
            }
        )

    def log_message(self, format, *args):
        return

    def respond(self, payload, status=200):
        body = json.dumps(payload, ensure_ascii=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    parser = argparse.ArgumentParser(description="YouTube RSS JSON proxy")
    parser.add_argument(
        "--host", default=os.environ.get("YOUTUBE_PROXY_HOST", "127.0.0.1")
    )
    parser.add_argument(
        "--port", type=int, default=int(os.environ.get("YOUTUBE_PROXY_PORT", "8095"))
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=int(os.environ.get("YOUTUBE_PROXY_TIMEOUT", "10")),
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=int(os.environ.get("YOUTUBE_PROXY_MAX_LIMIT", "25")),
    )
    args = parser.parse_args()

    Handler.default_channels = parse_csv(os.environ.get("YOUTUBE_CHANNEL_IDS", ""))
    Handler.default_playlists = parse_csv(os.environ.get("YOUTUBE_PLAYLIST_IDS", ""))
    Handler.timeout_seconds = max(2, args.timeout)
    Handler.max_limit = max(1, args.limit)

    with ThreadingHTTPServer((args.host, args.port), Handler) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
