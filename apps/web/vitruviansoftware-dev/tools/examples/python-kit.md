---
layout: tools
title: "A tool in Python, with the kit"
description: "A tool written with the Python kit, installed into the tool's own folder, which says hello and counts with a preference."
permalink: /tools/examples/python-kit/
source: packages/vitruvian-sdk/samples/hello-python-kit/README.md
---
{%- comment -%}
  Written by tools/sync-site-tools/sync.py from packages/vitruvian-sdk.
  Do not edit it: change the source, then run
    bazel run //tools/sync-site-tools:sync
{%- endcomment -%}
{% raw %}
A tool with two commands, written with the Python kit: `hello` shows a short
message, and `count` keeps a number in a preference and shows it.

```sh
vitruvian-tool init ~/hello-py --id com.you.hello-py --name "Hello" --publisher "You" --template python-kit
/usr/bin/python3 -m pip install --target ~/hello-py/lib -r ~/hello-py/requirements.txt
vitruvian-tool run ~/hello-py --command hello --command count
```

The app starts a tool with Apple's `python3`, which has none of your
packages, so the kit is installed into `lib/` inside the tool's folder, and
the program looks there first:

```python
HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))

from vitruvian_tool_kit import Tool  # noqa: E402

tool = Tool(version="0.1.0")


@tool.command("hello")
def hello(app):
    app.notify.hud(icon="hand.wave", message="Hello from a Python tool, with the kit")


@tool.command("count")
def count(app):
    counted = app.storage.get(key="count").value + 1
    app.storage.set(key="count", value=counted)
    app.notify.hud(icon="number", message=f"Counted to {counted}")


tool.run()
```

Add the folder in Vitruvian, `lib/` and all: Settings, Features, Tools from
outside, Add a Tool.

## Drawing

[`samples/hello-panel-python`](https://github.com/VitruvianSoftware/vitruvian-sdk/tree/main/samples/hello-panel-python) is a tool of protocol 2,
written with the same kit: a counter the app draws in the island from blocks
the tool sends. The guide's "Drawing" says how. Its page:

```python
    def page(self):
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
        )
```
{% endraw %}
