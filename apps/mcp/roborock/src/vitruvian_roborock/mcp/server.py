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

"""Assembles the MCP server that `rrctl mcp` serves over stdio."""

from __future__ import annotations

from mcp.server.apps import Apps
from mcp.server.mcpserver import MCPServer

from vitruvian_roborock import __version__
from vitruvian_roborock.mcp import resources, tools

INSTRUCTIONS = (
    "Controls a Roborock vacuum through a local daemon. Call get_status first: it says whether "
    "anyone is logged in and whether the vacuum is reachable. If it reports authenticated=false, "
    "walk the user through setup_login before anything else."
)


def build_server(bridge: tools.Bridge | None = None) -> MCPServer:
    bridge = bridge or tools.Bridge()
    # MCPServer reads an extension's tools and resources once, when it is
    # constructed, so the MCP App half is assembled before the server exists.
    apps = Apps()
    tools.register_app_tools(apps, bridge)
    resources.register_app_resources(apps)
    server = MCPServer("vitruvian-roborock", version=__version__, instructions=INSTRUCTIONS, extensions=[apps])
    tools.register(server, bridge)
    resources.register(server, bridge)
    return server
