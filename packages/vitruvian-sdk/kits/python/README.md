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
