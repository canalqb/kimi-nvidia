"""Kimi Code <-> NVIDIA NIM shim.

Kimi Code 2.0.x always sends `prompt_cache_key` on OpenAI-protocol requests,
but NVIDIA's OpenAI-compatible endpoint rejects it with
"Validation: Unsupported parameter(s): `prompt_cache_key`" (HTTP 400).

This loopback proxy strips that field and forwards everything else untouched
(headers, streaming SSE, tools, reasoning_effort), so GLM-5.3 works in Kimi.

Run: pythonw nvidia_shim.py   (listens on 127.0.0.1:8878; exits silently if busy)
Remove: run uninstall.ps1, then restore base_url in
        ~/.kimi-code/config.toml to https://integrate.api.nvidia.com/v1
"""

import json
import socket
import ssl
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import http.client

LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = 8878
UP_HOST = "integrate.api.nvidia.com"
UP_TIMEOUT_S = 600
STRIP_PARAMS = {"prompt_cache_key"}

HOP_BY_HOP = {
    "host",
    "content-length",
    "transfer-encoding",
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailer",
    "upgrade",
    "expect",
    "accept-encoding",
}


class Shim(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def log_error(self, *args):
        pass

    def _read_body(self):
        try:
            length = int(self.headers.get("Content-Length", 0))
        except ValueError:
            length = 0
        return self.rfile.read(length) if length > 0 else b""

    def _strip(self, raw):
        if not raw or b"prompt_cache_key" not in raw:
            return raw
        try:
            obj = json.loads(raw)
            if isinstance(obj, dict):
                for key in STRIP_PARAMS:
                    obj.pop(key, None)
                return json.dumps(obj, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        except Exception:
            pass
        return raw

    def do_GET(self):
        if self.path.startswith("/health"):
            body = b"ok"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self._forward("GET", None)

    def do_POST(self):
        self._forward("POST", self._strip(self._read_body()))

    def do_DELETE(self):
        self._forward("DELETE", self._read_body())

    def do_PUT(self):
        self._forward("PUT", self._strip(self._read_body()))

    def _forward(self, method, body):
        headers = {}
        for name, value in self.headers.items():
            if name.lower() in HOP_BY_HOP:
                continue
            headers[name] = value
        if body is not None:
            headers["Content-Length"] = str(len(body))
        try:
            conn = http.client.HTTPSConnection(
                UP_HOST, timeout=UP_TIMEOUT_S, context=ssl.create_default_context()
            )
            conn.request(method, self.path, body=body, headers=headers)
            upstream = conn.getresponse()
        except Exception as exc:
            payload = json.dumps({"error": {"message": f"shim upstream error: {exc}"}}).encode()
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(payload)
            self.close_connection = True
            return

        self.send_response(upstream.status)
        for name, value in upstream.getheaders():
            if name.lower() in HOP_BY_HOP:
                continue
            self.send_header(name, value)
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        try:
            while True:
                chunk = upstream.read(4096)
                if not chunk:
                    break
                self.wfile.write(chunk)
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, socket.timeout):
            pass
        finally:
            conn.close()


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main():
    try:
        server = Server((LISTEN_HOST, LISTEN_PORT), Shim)
    except OSError:
        sys.exit(0)
    try:
        server.serve_forever(poll_interval=1.0)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
