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

"""The MCP resources: live status, the map, and the dashboard as an MCP App."""

from __future__ import annotations

import json

from mcp.server.apps import Apps
from mcp.server.mcpserver import MCPServer

from vitruvian_roborock.dashboard import dashboard_html
from vitruvian_roborock.mcp.tools import DASHBOARD_URI, Bridge

STATUS_URI = "roborock://status"
MAP_URI = "roborock://map.png"


def register_app_resources(apps: Apps) -> None:
    """The dashboard as an MCP App. Must run before the server is built."""
    apps.add_html_resource(
        DASHBOARD_URI,
        dashboard_html(),
        name="dashboard",
        title="Roborock dashboard",
        description="Live map and status for the vacuum.",
    )


def register(server: MCPServer, bridge: Bridge) -> None:
    @server.resource(STATUS_URI, name="status", title="Vacuum status", mime_type="application/json")
    async def status() -> str:
        """The same document as the get_status tool."""
        return json.dumps(await bridge.safe("status"), indent=2)

    @server.resource(MAP_URI, name="map", title="Vacuum map", mime_type="image/png")
    async def map_png() -> bytes:
        """The current floor map as a PNG."""
        png = await bridge.call("map_png")
        if png is None:
            raise ValueError("The vacuum has not sent a map yet.")
        return png
