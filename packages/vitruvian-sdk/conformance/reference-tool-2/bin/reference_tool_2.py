#!/usr/bin/env python3
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
"""The smallest tool that speaks the Vitruvian tool protocol, version 2.

It is the first reference tool, `conformance/reference-tool`, plus one panel.
The command `hello` asks the app to show a short message. The panel `hello`
is a page in the island: a line of text and a button. The app draws it from
the blocks this program sends. Pressing the button gets a new page.

What version 2 adds, as this program uses it:

  ui/open    the app asks for the panel's first page; the answer holds it
  ui/event   the person pressed the button; the answer holds the next page
  ui/close   the panel went away; nothing to do

It uses nothing but Python: the protocol is one JSON message per line on
standard input and output.
"""

import json
import sys


def send(message):
    sys.stdout.write(json.dumps(message, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def page(presses):
    """The panel's page: a line of text and a button, as blocks."""
    if presses == 0:
        words = "Hello. Press the button."
    elif presses == 1:
        words = "Pressed once."
    else:
        words = f"Pressed {presses} times."
    return {
        "blocks": [
            {"type": "text", "text": words},
            {"type": "button", "id": "press", "title": "Press me"},
        ]
    }


def main():
    asked = 0
    presses = 0
    # A request of ours the app has not answered yet, and the `command/run`
    # it is part of.
    waiting = {}
    for line in sys.stdin:
        if not line.strip():
            continue
        message = json.loads(line)
        method = message.get("method")
        params = message.get("params", {})
        if method == "initialize":
            if "2" not in params["protocolVersions"]:
                error = {"code": -32602, "message": "this tool speaks protocol 2 only"}
                send({"jsonrpc": "2.0", "id": message["id"], "error": error})
                continue
            result = {"protocolVersion": "2", "toolVersion": "0.1.0"}
            send({"jsonrpc": "2.0", "id": message["id"], "result": result})
            send(
                {
                    "jsonrpc": "2.0",
                    "method": "commands/state",
                    "params": {"runnable": ["hello"]},
                }
            )
        elif method == "command/run":
            if params["command"] != "hello":
                error = {"code": -32602, "message": "no such command"}
                send({"jsonrpc": "2.0", "id": message["id"], "error": error})
                continue
            asked += 1
            waiting[asked] = message["id"]
            hud = {"icon": "hand.wave", "message": "Hello from reference tool 2"}
            send({"jsonrpc": "2.0", "id": asked, "method": "notify/hud", "params": hud})
        elif method == "ui/open":
            if params["panel"] != "hello":
                error = {"code": -32602, "message": "no such panel"}
                send({"jsonrpc": "2.0", "id": message["id"], "error": error})
                continue
            result = {"tree": page(presses)}
            send({"jsonrpc": "2.0", "id": message["id"], "result": result})
        elif method == "ui/event":
            pressed = (
                params["panel"] == "hello"
                and params.get("block") == "press"
                and params.get("event") == "tap"
            )
            if pressed:
                presses += 1
                result = {"tree": page(presses)}
            else:
                # Anything else leaves the page as it is.
                result = {"keep": True}
            # A tool sends ui/render only when it has news on its own.
            send({"jsonrpc": "2.0", "id": message["id"], "result": result})
        elif method == "ui/close":
            pass
        elif method == "shutdown":
            return 0
        elif method is None and message.get("id") in waiting:
            run = waiting.pop(message["id"])
            if "error" in message:
                error = {
                    "code": -32010,
                    "message": "command refused",
                    "data": message["error"],
                }
                send({"jsonrpc": "2.0", "id": run, "error": error})
            else:
                send({"jsonrpc": "2.0", "id": run, "result": {}})
        elif method is not None and "id" in message:
            error = {"code": -32601, "message": "method not found"}
            send({"jsonrpc": "2.0", "id": message["id"], "error": error})
    return 0


if __name__ == "__main__":
    sys.exit(main())
