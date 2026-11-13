#!/usr/bin/env python3
"""Tiny static server for the exported web build.

    python3 tools/serve_web.py [port]

Why not `python -m http.server`?  Because .wasm and .pck must be served with the
right MIME types or the browser refuses to stream them.  This adds them.
"""
import functools
import http.server
import mimetypes
import os
import socketserver
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "web")
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8000

mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("application/octet-stream", ".pck")
mimetypes.add_type("text/javascript", ".js")


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # the build is the single threaded template, so no COOP/COEP needed
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):  # keep the console quiet
        pass


if not os.path.isdir(ROOT):
    sys.exit("build/web is missing - run tools/build_web.sh first")

Handler.directory = ROOT
with socketserver.TCPServer(("0.0.0.0", PORT), functools.partial(Handler, directory=ROOT)) as httpd:
    print(f"serving {os.path.abspath(ROOT)} on http://0.0.0.0:{PORT}")
    httpd.serve_forever()
