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

"""What each `rrctl` subcommand does. Every function returns a process exit code."""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import sys
import webbrowser
from pathlib import Path
from typing import Any

from vitruvian_roborock.core import auth, config
from vitruvian_roborock.daemon import client as daemon_client
from vitruvian_roborock.daemon.client import DaemonClient, DaemonRequestError, DaemonUnavailable


def _say(message: str) -> None:
    print(message)


def _fail(message: str) -> int:
    print(f"rrctl: {message}", file=sys.stderr)
    return 1


def _client(args: argparse.Namespace) -> DaemonClient:
    return daemon_client.ensure_running(getattr(args, "port", None))


def _guarded(run: Any) -> Any:
    """Turn the daemon's refusals into one line on stderr instead of a traceback."""

    def wrapper(args: argparse.Namespace) -> int:
        try:
            return run(args)
        except DaemonRequestError as err:
            return _fail(str(err))
        except (DaemonUnavailable, config.ConfigError) as err:
            return _fail(str(err))

    wrapper.__name__ = run.__name__
    wrapper.__doc__ = run.__doc__
    return wrapper


def setup(args: argparse.Namespace) -> int:
    """Log in with an emailed code and store the result."""
    try:
        return asyncio.run(_setup(args))
    except auth.AuthError as err:
        return _fail(str(err))
    except (KeyboardInterrupt, EOFError):
        return _fail("setup cancelled.")


async def _setup(args: argparse.Namespace) -> int:
    status = auth.auth_status()
    if status.authenticated and not args.force:
        _say(f"Already logged in as {config.mask_email(status.email or '')}.")
        if status.migrated_from:
            _say(f"(Login was copied from {status.migrated_from}.)")
        _say("Use `rrctl setup --force` to log in again.")
        return 0
    email = args.email or input("Roborock account email: ")
    flow = auth.LoginFlow()
    await flow.request_code(email)
    _say("Roborock has emailed you a verification code.")
    code = input("Verification code: ")
    await flow.complete(email, code)
    _say(f"Logged in. Credentials saved to {config.credentials_path()} (readable only by you).")
    probe = DaemonClient(getattr(args, "port", None))
    if probe.health() is not None:
        try:
            probe.reload()
            _say("The running daemon picked up the new login.")
        except (DaemonUnavailable, DaemonRequestError) as err:
            _say(f"Restart the daemon to use the new login ({err}).")
    return 0


def _format_status(status: dict[str, Any]) -> str:
    if not status.get("authenticated"):
        return str(status.get("hint") or auth.SETUP_HINT)
    if not status.get("connected") and status.get("state") is None:
        return f"Not connected to the vacuum: {status.get('error') or 'still connecting'}"
    device = status.get("device") or {}
    lines = [f"{device.get('name') or 'Vacuum'}: {status.get('state') or 'unknown'}"]
    if status.get("battery") is not None:
        lines.append(f"  battery   {status['battery']}%")
    if status.get("error"):
        lines.append(f"  error     {status['error']}")
    if status.get("in_cleaning") or status.get("clean_time_s"):
        minutes = (status.get("clean_time_s") or 0) // 60
        area = status.get("clean_area_m2")
        lines.append(f"  cleaned   {area if area is not None else '?'} m2 in {minutes} min")
    for label, key in (("suction", "fan_speed"), ("water", "water_mode"), ("route", "mop_route")):
        if status.get(key):
            lines.append(f"  {label:<9} {status[key]}")
    rooms = ", ".join(str(room["name"]) for room in status.get("rooms") or [])
    if rooms:
        lines.append(f"  rooms     {rooms}")
    if not status.get("connected"):
        lines.append(f"  (last known; currently unreachable: {status.get('error')})")
    return "\n".join(lines)


@_guarded
def status(args: argparse.Namespace) -> int:
    """Show what the vacuum is doing."""
    doc = _client(args).status()
    _say(json.dumps(doc, indent=2) if args.json else _format_status(doc))
    return 0 if doc.get("connected") else 1


@_guarded
def map_(args: argparse.Namespace) -> int:
    """Save the current map as a PNG."""
    png = _client(args).map_png()
    if png is None:
        return _fail("the vacuum has not sent a map yet. Try again in a few seconds.")
    if args.output == "-":
        sys.stdout.buffer.write(png)
        return 0
    path = Path(args.output).expanduser()
    path.write_bytes(png)
    _say(f"Map saved to {path}")
    return 0


def _action(name: str, done: str) -> Any:
    @_guarded
    def run(args: argparse.Namespace) -> int:
        _client(args).command(name)
        _say(done)
        return 0

    run.__name__ = name
    return run


pause = _action("pause", "Paused.")
resume = _action("resume", "Resumed.")
dock = _action("dock", "Returning to the dock.")


def daemon(args: argparse.Namespace) -> int:
    """Run, start, stop or inspect the background daemon."""
    action = args.daemon_action or "run"
    port = getattr(args, "port", None)
    if action == "run":
        from vitruvian_roborock.daemon import server

        logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
        try:
            asyncio.run(server.serve(port))
        except server.PortInUse as err:
            return _fail(str(err))
        except KeyboardInterrupt:
            pass
        return 0
    probe = DaemonClient(port)
    health = probe.health()
    if action == "status":
        if health is None:
            _say(f"Daemon is not running on port {probe.port}.")
            return 1
        _say(f"Daemon {health.get('version')} is running on {probe.base_url} (pid {health.get('pid')}).")
        return 0
    if action == "stop":
        if health is None:
            _say("Daemon is not running.")
            return 0
        try:
            probe.shutdown()
        except (DaemonUnavailable, DaemonRequestError) as err:
            return _fail(str(err))
        _say("Daemon stopped.")
        return 0
    try:
        started = daemon_client.ensure_running(port)
    except DaemonUnavailable as err:
        return _fail(str(err))
    _say(f"Daemon is running on {started.base_url}. Log: {config.log_path()}")
    return 0


def mcp(args: argparse.Namespace) -> int:
    """Serve the MCP tools over stdio."""
    from vitruvian_roborock.mcp import server

    # stdout carries the protocol, so anything we log must go to stderr.
    logging.basicConfig(level=logging.WARNING, stream=sys.stderr)
    server.build_server().run("stdio")
    return 0


@_guarded
def dashboard(args: argparse.Namespace) -> int:
    """Open the live dashboard in a browser."""
    client = _client(args)
    token = config.read_token() or ""
    # The token rides in the fragment, which browsers never send to a server or
    # write to an access log; the page moves it into sessionStorage and clears it.
    url = f"{client.base_url}/#token={token}"
    if args.no_open:
        _say(url)
        return 0
    _say(f"Opening {client.base_url}/")
    if not webbrowser.open(url):
        _say(f"Could not open a browser. Open this yourself:\n{url}")
    return 0
