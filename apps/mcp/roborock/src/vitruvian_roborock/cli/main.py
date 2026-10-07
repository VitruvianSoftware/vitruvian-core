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

"""`rrctl`: the command-line entrypoint."""

from __future__ import annotations

import argparse
from collections.abc import Sequence

from vitruvian_roborock import __version__
from vitruvian_roborock.cli import commands


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="rrctl", description="Control a Roborock vacuum from this machine.")
    parser.add_argument("--version", action="version", version=f"rrctl {__version__}")
    parser.add_argument(
        "--port", type=int, default=None, help="daemon port (default 8765, or $VITRUVIAN_ROBOROCK_PORT)"
    )
    sub = parser.add_subparsers(dest="command", required=True, metavar="command")

    setup = sub.add_parser("setup", help="log in to Roborock with an emailed code")
    setup.add_argument("--email", help="account email (prompted if omitted)")
    setup.add_argument("--force", action="store_true", help="log in again even if a login is stored")
    setup.set_defaults(run=commands.setup)

    status = sub.add_parser("status", help="show what the vacuum is doing")
    status.add_argument("--json", action="store_true", help="print the raw status document")
    status.set_defaults(run=commands.status)

    map_ = sub.add_parser("map", help="save the current map as a PNG")
    map_.add_argument("-o", "--output", default="roborock-map.png", help="file to write, or - for stdout")
    map_.set_defaults(run=commands.map_)

    sub.add_parser("pause", help="pause cleaning").set_defaults(run=commands.pause)
    sub.add_parser("resume", help="resume a paused clean").set_defaults(run=commands.resume)
    sub.add_parser("dock", help="send the vacuum back to its dock").set_defaults(run=commands.dock)

    daemon = sub.add_parser("daemon", help="run or manage the background daemon")
    daemon.add_argument(
        "daemon_action",
        nargs="?",
        choices=("run", "start", "stop", "status"),
        default="run",
        help="run in the foreground (default), start in the background, stop, or report",
    )
    daemon.set_defaults(run=commands.daemon)

    sub.add_parser("mcp", help="serve the MCP tools over stdio").set_defaults(run=commands.mcp)

    dashboard = sub.add_parser("dashboard", help="open the live dashboard in a browser")
    dashboard.add_argument("--no-open", action="store_true", help="print the URL instead of opening it")
    dashboard.set_defaults(run=commands.dashboard)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return int(args.run(args))
