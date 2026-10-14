# A tool that draws, in Python, with the kit

A counter the app draws in the island, from blocks the tool sends, with a
button and a field; a switch in Settings; a command, `addOne`, that counts
too and sends the open page again; and a status, the small mark the app draws
on the closed island, with a pop-up menu to pick it. The same tool as `hello-panel-swift`,
written with the Python kit.

```sh
/usr/bin/python3 -m pip install --target samples/hello-panel-python/lib -r samples/hello-panel-python/requirements.txt
vitruvian-tool run samples/hello-panel-python --command addOne
```

A page is `tree` of its blocks, one function for each kind; a block that is
`None` is left out:

```python file=samples/hello-panel-python/bin/tool.py
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
            self.words_picker() if app.supports(Feature.STATUS_ACTIVITY) else None,
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
        if counter.words == "count":
            counter.show_status(app)
    elif event.block == "name":
        counter.name = event.text if event.text is not None else counter.name
    elif event.block == "status":
        # A pick is the event change, as leaving a field changed is.
        if event.text not in STATUSES:
            return PanelAnswer.keep()
        counter.status = event.text
        counter.show_status(app)
    elif event.block == "words":
        if event.text not in WORDS:
            return PanelAnswer.keep()
        counter.words = event.text
        if event.text == "seconds":
            counter.since = datetime.now(timezone.utc)
        counter.show_status(app)
    else:
        return PanelAnswer.keep()
    return PanelAnswer.page(counter.page(app))


island = tool.panel(
    "counter", on_open=lambda app, panel: counter.page(app), on_event=island_event
)
```

```python file=samples/hello-panel-python/bin/tool.py
@tool.command("addOne")
def add_one(app):
    counter.count += counter.step
    island.render(counter.page(app))
```

## A status, and a choice

The tool's status is a small mark the app draws on the closed island. The
manifest declares it, `"status": { "placement": "island" }` under
`contributes`, and `app.status` sets it: `none`, `ok`, `busy`, `attention` or
`failure`, with a line for VoiceOver. It needs nothing in `uses`.

```python file=samples/hello-panel-python/bin/tool.py
    def show_status(self, app):
        """Sets the mark on the closed island. Nothing is sent to an app that
        has no status, and the call says so."""
        # An app before 3.50 is sent the status without the words.
        return app.status(
            self.status,
            text=STATUSES[self.status][1],
            activity=str(self.count) if self.words == "count" else None,
            since=self.since if self.words == "seconds" else None,
        )

    def settings(self):
        """The Settings page."""
        return tree(
            toggle("byTwo", "Count by two", self.by_two),
            text("The island's counter adds this much each time.", style="caption"),
        )
```

The mark goes when the tool's program ends, so the tool sets it each time it
starts, and its manifest says `"activation": ["onLaunch"]` so that it starts
with the app:

```python file=samples/hello-panel-python/bin/tool.py
def start(app):
    """The status goes when the program ends, so it is set each time the
    program starts. The app may refuse any request: the tool carries on
    without."""
    try:
        counter.show_status(app)
    except Refusal as refusal:
        app.log(message=f"no status: {refusal}")


tool.on_start = start
```

The island page has a pop-up menu to pick the status with: a `choice` block.
Picking is the event `change`, with the option's value, as leaving a field
changed is. Both the status and the `choice` block are newer than protocol 2
itself, and Vitruvian 3.46 and 3.47 have neither. There `app.status` sends
nothing and returns False. A `choice` would be drawn as plain words nobody
can change, so the tool asks first and sends a field in its place:

```python file=samples/hello-panel-python/bin/tool.py
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
```

## A few words beside the mark

On Vitruvian 3.50 and later the status may carry a few words, drawn beside
the mark on the closed island, or a start time the app counts the seconds
from. The manifest says so, `"status": { "placement": "island", "activity":
true }`, and `app.status` takes `activity` and `since`. When the app has
them, `app.supports(Feature.STATUS_ACTIVITY)`, the island page gains a second
menu: None, the count, or seconds since it was picked. It starts at None, so
the sample does not take the place of what you read there until you ask. An
older app is sent the status without the words.

```python file=samples/hello-panel-python/bin/tool.py
    def words_picker(self):
        """The words beside the mark, to pick. It starts at None, so the
        sample does not take the place of what the person reads there until
        they ask."""
        options = [
            UIChoiceOption(value=value, title=title) for value, title in WORDS.items()
        ]
        return choice("words", self.words, options, title="Words on the closed island")
```

The manifest says `"protocol": "2"` and lists the two panels under
`contributes.panels`. The app starts a tool with Apple's `python3`, so the kit
is installed into `lib/` inside the folder, as `hello-python-kit` does. Add
the folder in Vitruvian, `lib/` and all: Settings, Features, Tools from
outside, Add a Tool.
