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

"""The MCP tools. Each one is a thin call to the daemon, never to the vacuum directly.

Tools answer with a plain document even when things are not set up: an agent can
read `{"ok": false, "error": "not_authenticated", "hint": ...}` and act on it,
where a raised exception would only tell it that something broke.
"""

from __future__ import annotations

import asyncio
from collections.abc import Callable
from typing import Any, Literal

from mcp.server.apps import Apps
from mcp.server.mcpserver import Image, MCPServer
from mcp.types import ToolAnnotations

from vitruvian_roborock.core import auth
from vitruvian_roborock.daemon import client as daemon_client
from vitruvian_roborock.daemon.client import DaemonClient, DaemonRequestError, DaemonUnavailable

DASHBOARD_URI = "ui://dashboard"

_READ_ONLY = ToolAnnotations(readOnlyHint=True, openWorldHint=False)
_ACTION = ToolAnnotations(readOnlyHint=False, destructiveHint=False, idempotentHint=True, openWorldHint=False)


class Bridge:
    """Runs blocking daemon calls off the event loop and turns failures into documents."""

    def __init__(
        self,
        client_factory: Callable[[], DaemonClient] = daemon_client.ensure_running,
        login_flow: auth.LoginFlow | None = None,
    ) -> None:
        self._client_factory = client_factory
        self.login_flow = login_flow or auth.LoginFlow()

    async def call(self, method: str, *args: Any) -> Any:
        def run() -> Any:
            return getattr(self._client_factory(), method)(*args)

        return await asyncio.to_thread(run)

    async def safe(self, method: str, *args: Any) -> dict[str, Any]:
        try:
            return await self.call(method, *args)
        except DaemonRequestError as err:
            doc = dict(err.payload)
            if err.code == "not_authenticated":
                doc.setdefault("hint", auth.SETUP_HINT)
            return doc
        except DaemonUnavailable as err:
            return {"ok": False, "error": "daemon_unavailable", "message": str(err)}

    async def reload_if_running(self) -> bool:
        def run() -> bool:
            probe = DaemonClient()
            if probe.health() is None:
                return False
            probe.reload()
            return True

        try:
            return await asyncio.to_thread(run)
        except (DaemonUnavailable, DaemonRequestError):
            return False


def register_app_tools(apps: Apps, bridge: Bridge) -> None:
    """Tools a host may render with the dashboard. Must run before the server is built."""

    @apps.tool(resource_uri=DASHBOARD_URI, title="Vacuum status", annotations=_READ_ONLY)
    async def get_status() -> dict[str, Any]:
        """What the vacuum is doing now: state, battery, any error, cleaning progress and its rooms.

        `authenticated: false` means nobody has logged in yet; use setup_login.
        `connected: false` means the vacuum or the Roborock cloud is unreachable.
        """
        return await bridge.safe("status")


def register(server: MCPServer, bridge: Bridge) -> None:
    @server.tool(title="Start cleaning", annotations=_ACTION)
    async def start_clean(rooms: list[str] | None = None, repeat: int = 1) -> dict[str, Any]:
        """Start cleaning. With no rooms, clean everywhere; otherwise only the named rooms.

        Room names come from get_status (`rooms`). `repeat` is how many passes, 1 to 3.
        """
        if rooms:
            return await bridge.safe("command", "clean_rooms", {"rooms": rooms, "repeat": repeat})
        return await bridge.safe("command", "start")

    @server.tool(title="Pause, resume, stop or locate", annotations=_ACTION)
    async def control(action: Literal["pause", "resume", "stop", "find"]) -> dict[str, Any]:
        """Pause or resume the current clean, stop it, or make the vacuum announce where it is."""
        return await bridge.safe("command", action)

    @server.tool(title="Return to dock", annotations=_ACTION)
    async def return_to_dock() -> dict[str, Any]:
        """Send the vacuum back to its dock to charge."""
        return await bridge.safe("command", "dock")

    @server.tool(title="Wash the mop", annotations=_ACTION)
    async def wash_mop(action: Literal["start", "stop"] = "start") -> dict[str, Any]:
        """Start or stop a mop wash at the dock. Only docks with a mop washer support this."""
        return await bridge.safe("command", f"wash_{action}")

    @server.tool(title="Vacuum map", annotations=_READ_ONLY, structured_output=False)
    async def get_map() -> Any:
        """The current floor map as a PNG image, with the vacuum's position and path."""
        try:
            png = await bridge.call("map_png")
        except DaemonRequestError as err:
            return err.payload.get("message") or str(err)
        except DaemonUnavailable as err:
            return str(err)
        if png is None:
            return "The vacuum has not sent a map yet. Check get_status, then try again."
        return Image(data=png, format="png")

    @server.tool(title="Log in to Roborock")
    async def setup_login(email: str, code: str | None = None) -> dict[str, Any]:
        """Log in to the Roborock cloud. Two calls.

        First call with only `email`: Roborock emails the user a verification code.
        Ask the user for it. Second call with `email` and `code`: the login is stored
        on this machine. Both calls must happen in the same session.
        """
        try:
            if code is None:
                await bridge.login_flow.request_code(email)
                return {
                    "ok": True,
                    "authenticated": False,
                    "next": "Roborock emailed a verification code. Ask the user for it, then call setup_login again with email and code.",
                }
            await bridge.login_flow.complete(email, code)
        except auth.AuthError as err:
            return {"ok": False, "error": "login_failed", "message": str(err)}
        reloaded = await bridge.reload_if_running()
        return {"ok": True, "authenticated": True, "daemon_reloaded": reloaded}
