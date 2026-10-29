---
layout: tools
title: "An example in Python"
description: "A tool in plain Python with nothing else: it says hello, and copies the time."
permalink: /tools/examples/python/
source: packages/vitruvian-sdk/samples/hello-python
---
{%- comment -%}
  Written by tools/sync-site-tools from packages/vitruvian-sdk.
  Do not edit it: change the source, then run
    bazel run //tools/sync-site-tools:sync
{%- endcomment -%}
{% raw %}
`vitruvian-tool init <folder>` starts a new tool from a copy of this one. The folder runs as it is: add it to Vitruvian.

This is [`samples/hello-python`](https://github.com/VitruvianSoftware/vitruvian-sdk/tree/main/samples/hello-python) of the SDK, as it is. The conformance script runs it in the SDK's tests.

`vitruvian-tool.json`:

```json
{
  "id": "dev.vitruvian.samples.hello-python",
  "name": { "en": "Hello, in Python" },
  "description": { "en": "Says hello, and copies the time." },
  "version": "0.1.0",
  "protocol": "1",
  "publisher": "VitruvianSoftware",
  "license": "MIT",
  "icon": "terminal",
  "uses": ["notify", "clipboard.write"],
  "contributes": {
    "commands": [
      {
        "id": "hello",
        "title": { "en": "Say hello from Python" },
        "icon": "hand.wave",
        "surfaces": ["commandBar", "radial", "quickPanel", "shortcut"]
      },
      {
        "id": "copyTime",
        "title": { "en": "Copy the time" },
        "icon": "clock",
        "surfaces": ["commandBar"]
      }
    ]
  },
  "activation": ["onCommand"],
  "runtime": { "kind": "external", "exec": "bin/tool.py" }
}
```

`bin/tool.py`:

```python
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
"""A tool in plain Python, with nothing but the standard library.

It has two commands: `hello` asks the app to show a short message, and
`copyTime` asks the app to put the time on the clipboard. The protocol is one
JSON message per line: the app's on standard input, the tool's on standard
output. Anything else the tool has to say goes to standard error, which is its
log. `vitruvian-tool init` starts a new tool from this file.
"""

import datetime
import json
import sys

VERSION = "0.1.0"

# What the app sent while a command waited for an answer. It is handled once
# that command has been answered.
kept = []
asked = 0


class Refused(Exception):
    """The app answered a request with a failure."""

    def __init__(self, error):
        super().__init__(error.get("message", "refused"))
        self.error = error


def send(message):
    sys.stdout.write(json.dumps(message, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def read():
    """The app's next message; None once the app has closed the link."""
    for line in sys.stdin:
        if line.strip():
            return json.loads(line)
    return None


def ask(method, params):
    """Asks the app for something, and waits for its answer."""
    global asked
    asked += 1
    send({"jsonrpc": "2.0", "id": asked, "method": method, "params": params})
    while True:
        message = read()
        if message is None or message.get("method") == "shutdown":
            sys.exit(0)
        if "method" not in message and message.get("id") == asked:
            if "error" in message:
                raise Refused(message["error"])
            return message["result"]
        kept.append(message)


def hello():
    ask("notify/hud", {"icon": "hand.wave", "message": "Hello from a Python tool"})


def copy_time():
    now = datetime.datetime.now().strftime("%H:%M:%S")
    ask("clipboard/writeText", {"text": now})
    ask("notify/hud", {"icon": "clock", "message": "Copied " + now})


COMMANDS = {"hello": hello, "copyTime": copy_time}


def handle(message):
    method, request = message.get("method"), message.get("id")
    if method == "initialize":
        if "1" not in message["params"]["protocolVersions"]:
            error = {"code": -32602, "message": "this tool speaks protocol 1 only"}
            return send({"jsonrpc": "2.0", "id": request, "error": error})
        result = {"protocolVersion": "1", "toolVersion": VERSION}
        return send({"jsonrpc": "2.0", "id": request, "result": result})
    if method == "command/run":
        command = COMMANDS.get(message["params"]["command"])
        if command is None:
            error = {"code": -32602, "message": "no such command"}
            return send({"jsonrpc": "2.0", "id": request, "error": error})
        try:
            command()
        except Refused as refused:
            error = {
                "code": -32010,
                "message": "command refused",
                "data": refused.error,
            }
            return send({"jsonrpc": "2.0", "id": request, "error": error})
        return send({"jsonrpc": "2.0", "id": request, "result": {}})
    if method == "shutdown":
        sys.exit(0)
    if method is not None and request is not None:
        error = {"code": -32601, "message": "method not found"}
        return send({"jsonrpc": "2.0", "id": request, "error": error})
    # A notice this tool has no use for, or an answer nobody waits for.
    return None


def main():
    while True:
        message = kept.pop(0) if kept else read()
        if message is None:
            return 0
        handle(message)


if __name__ == "__main__":
    sys.exit(main())
```
{% endraw %}
