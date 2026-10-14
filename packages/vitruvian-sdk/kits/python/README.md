# vitruvian-tool-kit

Write a tool for the [Vitruvian](https://vitruviansoftware.dev) Mac app in
Python. A tool is a folder with a `vitruvian-tool.json` and a program; the app
starts the program and talks to it over its standard input and output. This
kit is that conversation: you say what each command does, and call the app
from inside a command as an ordinary function call.

```python
from vitruvian_tool_kit import Tool

tool = Tool(version="0.1.0")


@tool.command("hello")
def hello(app):
    app.notify.hud(icon="hand.wave", message="Hello")


tool.run()
```

- **One call per message.** `app.notify.hud(...)`, `app.clipboard.read_text()`,
  `app.storage.get(key=...)`: each is one request of the protocol, named as
  the protocol names it. The app may refuse any of them; the call then raises
  `Refusal`. Raise `CommandRefused("why")` to refuse a command yourself.
- **Synchronous, on one thread.** A call to the app waits for its answer, ten
  seconds at most. A handler must not be `async`.
- **A tool can draw.** With `"protocol": "2"` and `panels` in its manifest,
  `tool.panel("counter", on_open=..., on_event=...)` says what a panel shows
  and what each thing the person does gives; a page is
  `tree(heading("Counter"), button("add", "Add one"))`, one function a kind
  of block. The handle sends a page unprompted with `render` and sets the
  tool's badge with `badge`.
- **A status, and a choice.** `app.status("busy", text=..., icon=...)` sets
  the small mark the app draws on the closed island, for a tool whose
  manifest declares `contributes.status`. `choice(id, value, options)` is a
  pop-up menu on a page. Both are newer than protocol 2 itself:
  `app.supports(Feature.CHOICE)` says whether this app has one. On an app
  from before them `app.status` sends nothing and returns False, and a
  `choice` is drawn as its fallback text, so send a `field` there instead.
- **Never `print`.** Standard output is the link to the app. Write to
  standard error, or call `app.log(message=...)`.

## Shipping it

The app starts a tool with Apple's `python3` (`/usr/bin/python3`, Python
3.9), which has none of your packages. So the kit goes inside the tool's
folder, and the program finds it there:

```sh
python3 -m pip install --target lib vitruvian-tool-kit
```

```python
import os, sys

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
```

`vitruvian-tool init --template python-kit` writes a tool set up this way.
The kit needs nothing but the standard library and Python 3.9 or later.

The whole guide, the protocol and the other kits are in
[the SDK](https://github.com/VitruvianSoftware/vitruvian-sdk). MIT licence.
