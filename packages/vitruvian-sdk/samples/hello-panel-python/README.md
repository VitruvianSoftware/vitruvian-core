# A tool that draws, in Python, with the kit

A counter the app draws in the island, from blocks the tool sends, with a
button and a field; a switch in Settings; and a command, `addOne`, that counts
too and sends the open page again. The same tool as `hello-panel-swift`,
written with the Python kit.

```sh
/usr/bin/python3 -m pip install --target samples/hello-panel-python/lib -r samples/hello-panel-python/requirements.txt
vitruvian-tool run samples/hello-panel-python --command addOne
```

A page is `tree` of its blocks, one function for each kind; a block that is
`None` is left out:

```python file=samples/hello-panel-python/bin/tool.py
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

`tool.panel` takes the two handlers by name: `on_open` gives the first page,
`on_event` answers what the person did with `PanelAnswer.page(tree)`,
`PanelAnswer.keep()`, `PanelAnswer.open(panel)` or `PanelAnswer.reply(value)`.
The handle it returns sends a page unprompted, with `render`, and sets the
tool's badge in the island, with `badge`:

```python file=samples/hello-panel-python/bin/tool.py
def island_event(app, panel, event):
    if event.block == "add":
        counter.count += counter.step
        panel.badge(count=counter.count)
    elif event.block == "name":
        counter.name = event.text if event.text is not None else counter.name
    else:
        return PanelAnswer.keep()
    return PanelAnswer.page(counter.page())


island = tool.panel(
    "counter", on_open=lambda app, panel: counter.page(), on_event=island_event
)
```

```python file=samples/hello-panel-python/bin/tool.py
@tool.command("addOne")
def add_one(app):
    counter.count += counter.step
    island.render(counter.page())
```

The manifest says `"protocol": "2"` and lists the two panels under
`contributes.panels`. The app starts a tool with Apple's `python3`, so the kit
is installed into `lib/` inside the folder, as `hello-python-kit` does. Add
the folder in Vitruvian, `lib/` and all: Settings, Features, Tools from
outside, Add a Tool.
