#!/usr/bin/env python3
"""HTTP fixture server for SSH proxy integration tests.

Serves:
  /        -> "cmux-ssh-forward-ok" (backward compat)
  /ip      -> JSON {"ip": "<client_source_ip>"} for egress validation
  /health  -> "ok"
"""

from __future__ import annotations

import argparse
import json
from http.server import HTTPServer, BaseHTTPRequestHandler


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        if self.path == "/ip":
            client_ip = self.client_address[0]
            body = json.dumps({"ip": client_ip}).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == "/health":
            body = b"ok"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            body = b"cmux-ssh-forward-ok"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        pass  # suppress access logs


def main() -> int:
    parser = argparse.ArgumentParser(description="HTTP fixture server")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=43173)
    args = parser.parse_args()

    server = HTTPServer((args.host, args.port), Handler)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
