#!/usr/bin/env python3
"""Serve the pod image on localhost, for the tests and for a look.

    python3 serve.py DIR PORT [--no-headers]

With the headers, each answer makes the page cross-origin isolated, as
BrowserPod needs. With --no-headers the page gets isolation from coi.js and
its service worker, as on a host that cannot set headers (GitHub Pages).
Range requests are answered: BrowserPod reads the home image in parts.
"""

import functools
import http.server
import os
import re
import sys


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".js": "text/javascript",
        ".mjs": "text/javascript",
        ".ext2": "application/octet-stream",
        ".json": "application/json",
    }
    headers_on = True

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        self.send_header("Accept-Ranges", "bytes")
        if self.headers_on:
            self.send_header("Cross-Origin-Opener-Policy", "same-origin")
            self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
            self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        super().end_headers()

    def send_head(self):
        match = re.fullmatch(r"bytes=(\d*)-(\d*)", self.headers.get("Range", ""))
        path = self.translate_path(self.path)
        if not match or not os.path.isfile(path):
            return super().send_head()
        size = os.path.getsize(path)
        first, last = match.groups()
        if first == "":
            first, last = max(0, size - int(last)), size - 1
        else:
            first, last = int(first), min(int(last) if last else size - 1, size - 1)
        if first > last or first >= size:
            self.send_error(416)
            return None
        f = open(path, "rb")
        f.seek(first)
        self.send_response(206)
        self.send_header("Content-Type", self.guess_type(path))
        self.send_header("Content-Range", f"bytes {first}-{last}/{size}")
        self.send_header("Content-Length", str(last - first + 1))
        self.end_headers()
        self.range_left = last - first + 1
        return f

    def copyfile(self, source, outputfile):
        left = getattr(self, "range_left", None)
        if left is None:
            return super().copyfile(source, outputfile)
        while left > 0:
            chunk = source.read(min(left, 1 << 16))
            if not chunk:
                break
            outputfile.write(chunk)
            left -= len(chunk)

    def send_header(self, keyword, value):
        # With PAW_SERVE_LOG, one line for each answer: the path and its bytes.
        log = os.environ.get("PAW_SERVE_LOG")
        if log and keyword == "Content-Length":
            with open(log, "a") as f:
                f.write(f"{self.path.split('?')[0]} {value}\n")
        super().send_header(keyword, value)

    def log_message(self, *args):
        pass


def main():
    root, port = sys.argv[1], int(sys.argv[2])
    Handler.headers_on = "--no-headers" not in sys.argv
    handler = functools.partial(Handler, directory=os.path.abspath(root))
    with http.server.ThreadingHTTPServer(("127.0.0.1", port), handler) as server:
        print(f"http://127.0.0.1:{port}/", flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()
