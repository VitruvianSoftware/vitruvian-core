# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

"""How the CLI and the MCP server talk to the daemon.

Standard library only and synchronous: both callers make one short request at a
time, and neither should need aiohttp just to ask for a status.
"""

from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from typing import Any

from vitruvian_roborock.core import config

SERVICE_NAME = "vitruvian-roborock"


class DaemonUnavailable(Exception):
    """Nothing usable is answering on the daemon's port."""


class DaemonRequestError(Exception):
    """The daemon answered, and the answer was a refusal."""

    def __init__(self, status: int, payload: dict[str, Any]) -> None:
        super().__init__(payload.get("message") or f"daemon returned HTTP {status}")
        self.status = status
        self.payload = payload

    @property
    def code(self) -> str:
        return str(self.payload.get("error") or "error")


class DaemonClient:
    def __init__(self, port: int | None = None, token: str | None = None, timeout: float = 15.0) -> None:
        self.port = port or config.daemon_port()
        self._token = token
        self._timeout = timeout
        # Loopback must never be sent through an HTTP(S)_PROXY from the environment.
        self._opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    @property
    def base_url(self) -> str:
        return f"http://{config.DAEMON_HOST}:{self.port}"

    def _request(self, method: str, path: str, body: dict[str, Any] | None = None, *, auth: bool = True) -> bytes:
        headers = {}
        if auth:
            token = self._token or config.read_token()
            if not token:
                raise DaemonUnavailable("No daemon token found. Start the daemon with `rrctl daemon start`.")
            headers["Authorization"] = f"Bearer {token}"
        data = None
        if method == "POST":
            data = json.dumps(body or {}).encode()
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(self.base_url + path, data=data, headers=headers, method=method)
        try:
            with self._opener.open(request, timeout=self._timeout) as response:
                return response.read()
        except urllib.error.HTTPError as err:
            raw = err.read()
            try:
                payload = json.loads(raw)
            except ValueError:
                payload = {}
            if not isinstance(payload, dict) or "error" not in payload:
                raise DaemonUnavailable(f"Port {self.port} is answering, but not as the Roborock daemon.") from err
            raise DaemonRequestError(err.code, payload) from err
        except (urllib.error.URLError, OSError) as err:
            raise DaemonUnavailable(f"The daemon is not reachable on {self.base_url}.") from err

    def _json(self, method: str, path: str, body: dict[str, Any] | None = None, *, auth: bool = True) -> dict[str, Any]:
        try:
            doc = json.loads(self._request(method, path, body, auth=auth))
        except ValueError as err:
            raise DaemonUnavailable(f"Port {self.port} is answering, but not as the Roborock daemon.") from err
        if not isinstance(doc, dict):
            raise DaemonUnavailable(f"Port {self.port} is answering, but not as the Roborock daemon.")
        return doc

    def health(self) -> dict[str, Any] | None:
        """The daemon's health document, or None when it is not ours or not up."""
        try:
            doc = self._json("GET", "/healthz", auth=False)
        except (DaemonUnavailable, DaemonRequestError):
            return None
        return doc if doc.get("service") == SERVICE_NAME else None

    def status(self) -> dict[str, Any]:
        return self._json("GET", "/status")

    def map_png(self) -> bytes | None:
        try:
            return self._request("GET", "/map.png")
        except DaemonRequestError as err:
            if err.code == "no_map":
                return None
            raise

    def command(self, action: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        body: dict[str, Any] = {"command": action}
        if params:
            body["params"] = params
        return self._json("POST", "/command", body)

    def reload(self) -> dict[str, Any]:
        return self._json("POST", "/reload")

    def shutdown(self) -> dict[str, Any]:
        return self._json("POST", "/shutdown")


def spawn_daemon(port: int | None = None) -> subprocess.Popen[bytes]:
    """Start the daemon as a background process that outlives the caller."""
    log = config.log_path()
    config.ensure_private_dir(log.parent)
    command = [sys.executable, "-m", "vitruvian_roborock"]
    if port:
        command += ["--port", str(port)]
    command += ["daemon", "run"]
    # 0600 from creation: the log names the account's devices.
    with os.fdopen(os.open(log, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600), "ab") as handle:
        return subprocess.Popen(  # noqa: S603 - fixed argv, our own interpreter
            command,
            stdin=subprocess.DEVNULL,
            stdout=handle,
            stderr=handle,
            start_new_session=True,
        )


def _port_taken(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.settimeout(0.5)
        return probe.connect_ex((config.DAEMON_HOST, port)) == 0


def ensure_running(port: int | None = None, *, wait: float = 15.0) -> DaemonClient:
    """Return a client for a live daemon, starting one if none is running."""
    client = DaemonClient(port)
    if client.health() is not None:
        return client
    if _port_taken(client.port):
        raise DaemonUnavailable(
            f"Port {client.port} is in use by another program, so the daemon cannot start. "
            f"Stop that program, or set {config.PORT_ENV} to a free port."
        )
    process = spawn_daemon(port)
    deadline = time.monotonic() + wait
    while time.monotonic() < deadline:
        if client.health() is not None:
            return client
        if process.poll() is not None:
            # Ours exited: either it failed, or another caller's daemon won the port first.
            if client.health() is not None:
                return client
            break
        time.sleep(0.2)
    raise DaemonUnavailable(f"The daemon did not start on port {client.port}. See {config.log_path()}.")
