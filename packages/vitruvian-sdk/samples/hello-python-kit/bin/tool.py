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
"""A tool written with the Python kit. It has two commands: `hello` asks the
app to show a short message, and `count` keeps a number in a preference its
manifest declares, counting by what another preference says. That one has
`options`, so the app draws it as a pop-up menu in the tool's detail. `vitruvian-tool init --template python-kit` starts a new
tool from this folder.

The app starts a tool with Apple's python3, which has none of your packages,
so the kit is installed into lib/ inside the tool's folder:

    python3 -m pip install --target lib -r requirements.txt
"""

import os
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))

from vitruvian_tool_kit import Tool  # noqa: E402

tool = Tool(version="0.1.0")


@tool.command("hello")
def hello(app):
    app.notify.hud(icon="hand.wave", message="Hello from a Python tool, with the kit")


@tool.command("count")
def count(app):
    # The step is saved as text. The options are how the app draws the
    # setting, not a rule on what is saved: an app before 3.48 draws a text
    # field, so anything may be there. What is no number counts as one.
    step = str(app.storage.get(key="step").value)
    counted = app.storage.get(key="count").value + (int(step) if step.isdigit() else 1)
    app.storage.set(key="count", value=counted)
    app.notify.hud(icon="number", message=f"Counted to {counted}")


tool.run()
