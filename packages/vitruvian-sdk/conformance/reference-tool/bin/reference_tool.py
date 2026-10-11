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
"""The smallest tool that speaks the Vitruvian tool protocol, version 1.

It has one command, `hello`, which asks the app to show a short message. It is
what the conformance script is proven against, and it uses nothing but Python:
the protocol is one JSON message per line on standard input and output.
"""

import json
import sys


def send(message):
    sys.stdout.write(json.dumps(message, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def main():
    asked = 0
    # A request of ours the app has not answered yet, and the `command/run`
    # it is part of.
    waiting = {}
    for line in sys.stdin:
        if not line.strip():
            continue
        message = json.loads(line)
        method = message.get("method")
        if method == "initialize":
            if "1" not in message["params"]["protocolVersions"]:
                error = {"code": -32602, "message": "this tool speaks protocol 1 only"}
                send({"jsonrpc": "2.0", "id": message["id"], "error": error})
                continue
            result = {"protocolVersion": "1", "toolVersion": "0.1.0"}
            send({"jsonrpc": "2.0", "id": message["id"], "result": result})
            send(
                {
                    "jsonrpc": "2.0",
                    "method": "commands/state",
                    "params": {"runnable": ["hello"]},
                }
            )
        elif method == "command/run":
            if message["params"]["command"] != "hello":
                error = {"code": -32602, "message": "no such command"}
                send({"jsonrpc": "2.0", "id": message["id"], "error": error})
                continue
            asked += 1
            waiting[asked] = message["id"]
            params = {"icon": "hand.wave", "message": "Hello from the reference tool"}
            send(
                {
                    "jsonrpc": "2.0",
                    "id": asked,
                    "method": "notify/hud",
                    "params": params,
                }
            )
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
