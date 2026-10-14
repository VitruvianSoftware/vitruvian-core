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
"""A tool that draws, written with the Python kit. Its page in the island is a
counter with a button and a field; its page in Settings is one switch. The app
draws both, from the blocks this program sends. The command `addOne` counts
too, and sends the open page again.

It also shows a status, the small mark the app draws on the closed island, and
its island page has a pop-up menu to pick it with. Both are newer than
protocol 2 itself, so the tool asks the app what it has.

The app starts a tool with Apple's python3, which has none of your packages,
so the kit is installed into lib/ inside the tool's folder:

    python3 -m pip install --target lib -r requirements.txt
"""

import os
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))

from vitruvian_tool_kit import (  # noqa: E402
    Feature,
    PanelAnswer,
    Refusal,
    Tool,
    UIChoiceOption,
    button,
    choice,
    field,
    heading,
    text,
    toggle,
    tree,
)

tool = Tool(version="0.1.0")

# What each status is called in the menu, and what it says to VoiceOver.
STATUSES = {
    "none": ("None", None),
    "ok": ("OK", "The counter is fine"),
    "busy": ("Busy", "The counter is counting"),
    "attention": ("Needs attention", "The counter wants a look"),
    "failure": ("Failed", "The counter failed"),
}


class Counter:
    """What the tool knows. One thread reads the link, so one object is enough."""

    def __init__(self):
        self.count = 0
        self.name = ""
        self.by_two = False
        # What the tool shows on the closed island.
        self.status = "ok"

    @property
    def step(self):
        return 2 if self.by_two else 1

    def page(self, app):
        """The island page: what it says now."""
        return tree(
            heading("Counter"),
            text(f"Pressed {self.count} times"),
            button("add", f"Add {self.step}", style="prominent"),
            field(
                "name",
                title="Your name",
                value=self.name,
                placeholder="Type it and press Return",
            ),
            text(f"Hello, {self.name}", style="secondary") if self.name else None,
            self.status_picker(app),
        )

    def status_picker(self, app):
        """The status, to pick: a pop-up menu where the app has one. An app
        before 3.48 draws a `choice` as plain words nobody can change, so
        there it is a field to type the word in."""
        if not app.supports(Feature.CHOICE):
            return field(
                "status",
                title="Status: none, ok, busy, attention or failure",
                value=self.status,
            )
        options = [
            UIChoiceOption(value=state, title=title)
            for state, (title, _) in STATUSES.items()
        ]
        return choice(
            "status", self.status, options, title="Status on the closed island"
        )

    def show_status(self, app):
        """Sets the mark on the closed island. Nothing is sent to an app that
        has no status, and the call says so."""
        return app.status(self.status, text=STATUSES[self.status][1])

    def settings(self):
        """The Settings page."""
        return tree(
            toggle("byTwo", "Count by two", self.by_two),
            text("The island's counter adds this much each time.", style="caption"),
        )


counter = Counter()


def island_event(app, panel, event):
    if event.block == "add":
        counter.count += counter.step
        panel.badge(count=counter.count)
    elif event.block == "name":
        counter.name = event.text if event.text is not None else counter.name
    elif event.block == "status":
        # A pick is the event change, as leaving a field changed is.
        if event.text not in STATUSES:
            return PanelAnswer.keep()
        counter.status = event.text
        counter.show_status(app)
    else:
        return PanelAnswer.keep()
    return PanelAnswer.page(counter.page(app))


island = tool.panel(
    "counter", on_open=lambda app, panel: counter.page(app), on_event=island_event
)


def settings_event(app, panel, event):
    if event.block != "byTwo" or event.is_on is None:
        return PanelAnswer.keep()
    counter.by_two = event.is_on
    return PanelAnswer.page(counter.settings())


tool.panel(
    "settings", on_open=lambda app, panel: counter.settings(), on_event=settings_event
)


@tool.command("addOne")
def add_one(app):
    counter.count += counter.step
    island.render(counter.page(app))


def start(app):
    """The status goes when the program ends, so it is set each time the
    program starts. The app may refuse any request: the tool carries on
    without."""
    try:
        counter.show_status(app)
    except Refusal as refusal:
        app.log(message=f"no status: {refusal}")


tool.on_start = start


tool.run()
