#!/usr/bin/env python3
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

AUTH_HOST = os.environ.get("AUTH_HOST", "127.0.0.1")
AUTH_PORT = int(os.environ.get("AUTH_PORT", "10302"))
AUTH_KEYS_FILE = os.environ.get(
    "AUTH_KEYS_FILE",
    "/usr/local/ifgame/iaf/server/UnityMCP/deploy/auth_keys.txt",
)


def load_keys():
    key_to_user = {}
    if not os.path.exists(AUTH_KEYS_FILE):
        return key_to_user

    with open(AUTH_KEYS_FILE, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if ":" not in line:
                continue
            user, key = line.split(":", 1)
            user = user.strip()
            key = key.strip()
            if user and key:
                key_to_user[key] = user

    return key_to_user


class Handler(BaseHTTPRequestHandler):
    server_version = "SimpleAuth/1.0"

    def _send_json(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._send_json(200, {"ok": True})
            return

        if self.path == "/api-keys":
            self._send_json(
                200,
                {
                    "message": "Ask admin for your UnityMCP API key.",
                    "format": "user:key stored in auth_keys.txt",
                },
            )
            return

        self._send_json(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/api/validate-key":
            self._send_json(404, {"error": "not found"})
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length)
            data = json.loads(raw.decode("utf-8")) if raw else {}
            api_key = str(data.get("api_key", "")).strip()
        except Exception:
            self._send_json(400, {"valid": False, "error": "invalid json"})
            return

        key_to_user = load_keys()
        user = key_to_user.get(api_key)

        if user:
            self._send_json(
                200,
                {
                    "valid": True,
                    "user_id": user,
                    "metadata": {"source": "file_auth"},
                },
            )
        else:
            self._send_json(200, {"valid": False, "error": "invalid api key"})

    def log_message(self, fmt, *args):
        print("[%s] %s" % (self.address_string(), fmt % args), flush=True)


if __name__ == "__main__":
    httpd = ThreadingHTTPServer((AUTH_HOST, AUTH_PORT), Handler)
    print("auth service listening on %s:%s" % (AUTH_HOST, AUTH_PORT), flush=True)
    httpd.serve_forever()
