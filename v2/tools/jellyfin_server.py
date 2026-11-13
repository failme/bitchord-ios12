#!/usr/bin/env python3
"""A small Jellyfin server for the iOS 12 CI run.

Implements the four calls the app makes: AuthenticateByName, the user's Views,
folder Items and the audio stream (with Range support). No dependencies.
"""

import argparse
import json
import os
import re
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TOKEN = "ci-jellyfin-token"
USER_ID = "ci-user-1"
LIBRARY_ID = "lib-music"
ALBUM_ID = "album-one"
TRACK_ID = "track-one"
TRACK_NAME = "track.m4a"


def item(identifier, name, kind, folder=False, album="", artists=None, ticks=0):
    return {
        "Id": identifier,
        "Name": name,
        "Type": kind,
        "IsFolder": folder,
        "Album": album,
        "Artists": artists or [],
        "RunTimeTicks": ticks,
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "BitChordJellyfin/1.0"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        print("%s - %s" % (self.address_string(), fmt % args), flush=True)

    def _json(self, status, payload, extra=None):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self):
        parsed = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(parsed.query)
        return (query.get("api_key") or [""])[0] == TOKEN

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        if self.path.split("?")[0] != "/Users/AuthenticateByName":
            self.send_error(404)
            return
        if "MediaBrowser" not in (self.headers.get("Authorization") or ""):
            self._json(400, {"error": "missing client header"})
            return
        try:
            body = json.loads(raw.decode("utf-8") or "{}")
        except Exception:
            self._json(400, {"error": "bad json"})
            return
        if body.get("Username") != self.server.user or body.get("Pw") != self.server.password:
            self._json(401, {"error": "invalid credentials"})
            return
        self._json(200, {
            "AccessToken": TOKEN,
            "ServerId": "ci-server",
            "User": {"Id": USER_ID, "Name": body.get("Username")},
        })

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/Users/%s/Views" % USER_ID:
            if not self._authorized():
                self._json(401, {"error": "unauthorized"})
                return
            self._json(200, {"Items": [
                item(LIBRARY_ID, "Music", "CollectionFolder", folder=True),
            ]})
            return
        if path == "/Users/%s/Items" % USER_ID:
            if not self._authorized():
                self._json(401, {"error": "unauthorized"})
                return
            query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            parent = (query.get("ParentId") or [""])[0]
            if parent == LIBRARY_ID:
                self._json(200, {"Items": [
                    item(ALBUM_ID, "Album One", "MusicAlbum", folder=True,
                         album="Album One", artists=["Fixture Artist"]),
                    item("track-loose", "Loose Track.m4a", "Audio", album="", artists=["Fixture Artist"],
                         ticks=40 * 10_000_000),
                ]})
                return
            if parent == ALBUM_ID:
                self._json(200, {"Items": [
                    item(TRACK_ID, TRACK_NAME, "Audio", album="Album One",
                         artists=["Fixture Artist"], ticks=40 * 10_000_000),
                ]})
                return
            self._json(200, {"Items": []})
            return
        match = re.match(r"^/Audio/([^/]+)/stream$", path)
        if match:
            if not self._authorized():
                self._json(401, {"error": "unauthorized"})
                return
            self._stream()
            return
        self.send_error(404)

    def _stream(self):
        size = os.path.getsize(self.server.media)
        range_header = self.headers.get("Range", "")
        start, end = 0, size - 1
        partial = False
        if range_header.startswith("bytes="):
            token = range_header.split("=", 1)[1].split(",")[0]
            first, _, last = token.partition("-")
            if first.strip():
                start = int(first)
                if last.strip():
                    end = min(int(last), size - 1)
            elif last.strip():
                start = max(0, size - int(last))
            partial = True
        if start > end or start >= size:
            self.send_response(416)
            self.send_header("Content-Range", "bytes */%d" % size)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        length = end - start + 1
        self.send_response(206 if partial else 200)
        self.send_header("Content-Type", "audio/mp4")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(length))
        if partial:
            self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
        self.end_headers()
        with open(self.server.media, "rb") as handle:
            handle.seek(start)
            remaining = length
            while remaining > 0:
                chunk = handle.read(min(64 * 1024, remaining))
                if not chunk:
                    break
                self.wfile.write(chunk)
                remaining -= len(chunk)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8792)
    parser.add_argument("--user", default="demo")
    parser.add_argument("--password", default="secret")
    parser.add_argument("--media", required=True)
    args = parser.parse_args()

    server = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    server.user = args.user
    server.password = args.password
    server.media = os.path.abspath(args.media)
    print("Jellyfin fixture on :%d serving %s" % (args.port, server.media), flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
