"""Thin tunneld agent API client (no policy). The HTTP API is the product."""
import os
import urllib.request
import urllib.error
import json


class TunneldError(RuntimeError):
    pass


class TunneldClient:
    def __init__(self, url=None, token=None, timeout=30):
        self.url = (url or os.environ.get("TUNNELD_URL") or "http://10.0.0.1").rstrip("/")
        self.token = token or os.environ.get("TUNNELD_TOKEN")
        if not self.token:
            raise TunneldError("TUNNELD_TOKEN required (issue via: mix tunneld.issue_token ...)")
        self.timeout = timeout

    def _request(self, method, path, body=None):
        req = urllib.request.Request(self.url + path, method=method)
        req.add_header("Authorization", "Bearer " + self.token)
        req.add_header("Content-Type", "application/json")
        data = json.dumps(body).encode() if body is not None else None
        try:
            with urllib.request.urlopen(req, data=data, timeout=self.timeout) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            msg = e.read().decode(errors="replace")
            raise TunneldError(f"HTTP {e.code}: {msg}") from e

    def machines(self):
        return self._request("GET", "/api/v1/agent/machines")

    def machine(self, id):
        return self._request("GET", f"/api/v1/agent/machines/{id}")

    def listeners(self, id):
        return self._request("GET", f"/api/v1/agent/machines/{id}/listeners")

    def probe(self, id):
        return self._request("POST", f"/api/v1/agent/machines/{id}/probe")

    def exec(self, id, cmd):
        return self._request("POST", f"/api/v1/agent/machines/{id}/exec", {"cmd": cmd})

    def jobs(self, id):
        return self._request("GET", f"/api/v1/agent/jobs/{id}")

    def resources(self):
        return self._request("GET", "/api/v1/agent/resources")

    def add_resource(self, name, pool):
        return self._request("POST", "/api/v1/agent/resources", {"name": name, "pool": pool})

    def rm_resource(self, id):
        return self._request("DELETE", f"/api/v1/agent/resources/{id}")
