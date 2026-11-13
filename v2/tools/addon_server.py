#!/usr/bin/env python3
"""A tiny test addon for the CI run.

Speaks the same two calls the app's AddonService uses:

    GET /manifest            -> {"name": "Studio addon", "lossless": true}
    GET /stream/<videoID>    -> {"url": "...", "quality": "Lossless", "kbps": ...}

plus one test-only control call, `/serve/<videoID>`, which tells it which single
track it is able to serve. Every other track gets a 404, which is how the app's
clean fallback to the standard catalogue is exercised.

It serves whatever media file it is pointed at; CI generates a lossless ALAC
tone so the fetched bytes really are a different, higher-bitrate file.
"""
import argparse
import json
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SERVE_ID = {"value": None}
MEDIA = {"path": None, "port": None}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _json(self, payload, status=200):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/manifest":
            return self._json({"name": "Studio addon", "lossless": True})

        if self.path.startswith("/serve/"):
            SERVE_ID["value"] = self.path[len("/serve/"):]
            return self._json({"serving": SERVE_ID["value"]})

        if self.path.startswith("/stream/"):
            video_id = self.path[len("/stream/"):]
            if not SERVE_ID["value"] or video_id != SERVE_ID["value"]:
                return self._json({"error": "no stream for this track"}, 404)
            url = "http://127.0.0.1:%d/media/%s" % (
                MEDIA["port"], os.path.basename(MEDIA["path"]))
            return self._json({"url": url, "quality": "Lossless", "kbps": 1411})

        if self.path.startswith("/media/"):
            if not MEDIA["path"] or not os.path.exists(MEDIA["path"]):
                return self._json({"error": "no media"}, 404)
            with open(MEDIA["path"], "rb") as handle:
                data = handle.read()
            self.send_response(200)
            self.send_header("Content-Type", "audio/mp4")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return

        return self._json({"error": "not found"}, 404)

    def log_message(self, *args):
        pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--media", required=True)
    args = parser.parse_args()
    MEDIA["path"] = args.media
    MEDIA["port"] = args.port
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
