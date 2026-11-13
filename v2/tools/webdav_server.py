#!/usr/bin/env python3
"""A small WebDAV server for the iOS 12 CI run.

It implements the two methods the app uses: PROPFIND (Depth: 1, with the
DAV: multistatus document) and GET with Range support, behind Basic auth.
No external dependencies, so the runner needs nothing installed.
"""

import argparse
import base64
import os
import posixpath
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from xml.sax.saxutils import escape

PROPFIND_BODY = b"""<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:"><D:prop>
<D:resourcetype/><D:getcontentlength/><D:getcontenttype/><D:displayname/>
</D:prop></D:propfind>"""


class AuthError(Exception):
    pass


def basic_ok(header, user, password):
    if not header or not header.startswith("Basic "):
        return False
    try:
        raw = base64.b64decode(header[6:]).decode("utf-8")
    except Exception:
        return False
    return raw == f"{user}:{password}"


class Handler(BaseHTTPRequestHandler):
    server_version = "BitChordFixture/1.0"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        print("%s - %s" % (self.address_string(), fmt % args), flush=True)

    def _authorized(self):
        if basic_ok(self.headers.get("Authorization"), self.server.user, self.server.password):
            return True
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="bitChord"')
        self.send_header("Content-Length", "0")
        self.end_headers()
        return False

    def _local_path(self):
        parsed = urllib.parse.urlparse(self.path)
        relative = urllib.parse.unquote(parsed.path).lstrip("/")
        relative = posixpath.normpath(relative) if relative else ""
        if relative in (".", "/"):
            relative = ""
        candidate = os.path.normpath(os.path.join(self.server.root, relative))
        if not candidate.startswith(self.server.root):
            return None
        return candidate

    def do_PROPFIND(self):
        if not self._authorized():
            return
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            self.rfile.read(length)
        target = self._local_path()
        if not target or not os.path.exists(target):
            self.send_error(404)
            return

        entries = [target]
        if os.path.isdir(target):
            entries += [os.path.join(target, name) for name in sorted(os.listdir(target))]

        parts = []
        for path in entries:
            relative = os.path.relpath(path, self.server.root)
            href = "/" if relative == "." else "/" + urllib.parse.quote(relative.replace(os.sep, "/"))
            if os.path.isdir(path):
                href += "/"
                resource = "<D:resourcetype><D:collection/></D:resourcetype>"
                content_type = ""
                size = ""
            else:
                resource = "<D:resourcetype/>"
                content_type = "<D:getcontenttype>%s</D:getcontenttype>" % (
                    "audio/mp4" if path.endswith(".m4a") else "application/octet-stream"
                )
                size = "<D:getcontentlength>%d</D:getcontentlength>" % os.path.getsize(path)
            name = escape(os.path.basename(path) or "/")
            parts.append(
                "<D:response><D:href>%s</D:href><D:propstat><D:prop>%s%s"
                "<D:displayname>%s</D:displayname></D:prop>"
                "<D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>"
                % (href, resource, size + content_type, name)
            )

        body = (
            '<?xml version="1.0" encoding="utf-8"?>'
            '<D:multistatus xmlns:D="DAV:">' + "".join(parts) + "</D:multistatus>"
        ).encode("utf-8")
        self.send_response(207)
        self.send_header("Content-Type", "application/xml; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_HEAD(self):
        if not self._authorized():
            return
        length = self._file_length()
        if length is None:
            return
        self.send_response(200)
        self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Type", "audio/mp4")
        self.end_headers()

    def do_GET(self):
        if not self._authorized():
            return
        target = self._local_path()
        if not target or not os.path.isfile(target):
            self.send_error(404)
            return
        size = os.path.getsize(target)
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
        with open(target, "rb") as handle:
            handle.seek(start)
            remaining = length
            while remaining > 0:
                chunk = handle.read(min(64 * 1024, remaining))
                if not chunk:
                    break
                self.wfile.write(chunk)
                remaining -= len(chunk)

    def _file_length(self):
        target = self._local_path()
        if not target or not os.path.isfile(target):
            self.send_error(404)
            return None
        return os.path.getsize(target)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8791)
    parser.add_argument("--user", default="demo")
    parser.add_argument("--password", default="secret")
    parser.add_argument("--root", required=True)
    args = parser.parse_args()

    server = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    server.root = os.path.abspath(args.root)
    server.user = args.user
    server.password = args.password
    print("WebDAV fixture on :%d serving %s" % (args.port, server.root), flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
