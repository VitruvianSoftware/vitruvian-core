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
"""A tool that draws: its panels, what the person did in one, how a handler
answers, and a page written as the blocks it holds. The Swift kit's
Panels.swift, in Python."""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, Any, Callable, Dict, List, Optional

from .generated.messages import (
    ButtonBlock,
    ChipsBlock,
    ChoiceBlock,
    DividerBlock,
    FieldBlock,
    HeadingBlock,
    ImageBlock,
    LinkBlock,
    ListBlock,
    ProgressBlock,
    RowBlock,
    SpacerBlock,
    TextBlock,
    ToggleBlock,
    UIBlock,
    UIChipOption,
    UIChoiceOption,
    UIListRow,
    UIRenderParams,
    UIText,
    UITree,
)

if TYPE_CHECKING:
    from .tool import App, Tool


@dataclass(frozen=True)
class PanelEvent:
    """What the person did in one of the tool's panels, as a handler sees it."""

    block: Optional[str]
    """The block's id, as the page gave it. None for a web page's call."""
    kind: str
    """tap, toggle, submit, change or bridge."""
    value: Any = None

    @property
    def row(self) -> Optional[str]:
        """For a tap on a row of a list: the row's id."""
        return (
            self.value if self.kind == "tap" and isinstance(self.value, str) else None
        )

    @property
    def text(self) -> Optional[str]:
        """For submit and change: the field's text. For the change of a
        choice: the picked option's value."""
        if self.kind in ("submit", "change") and isinstance(self.value, str):
            return self.value
        return None

    @property
    def is_on(self) -> Optional[bool]:
        """For toggle: the switch's new state."""
        return (
            self.value
            if self.kind == "toggle" and isinstance(self.value, bool)
            else None
        )

    @property
    def values(self) -> Optional[List[str]]:
        """For the change of chips: the values of every option now on, in
        the options' order, and none when the last was turned off."""
        if (
            self.kind == "change"
            and isinstance(self.value, list)
            and all(isinstance(item, str) for item in self.value)
        ):
            return list(self.value)
        return None


@dataclass(frozen=True)
class PanelAnswer:
    """How a handler answers what the person did. Made with one of its four
    constructors: `PanelAnswer.page(tree)`, the next page;
    `PanelAnswer.keep()`, the page stays as it is; `PanelAnswer.open(panel)`,
    one of the tool's window panels opens, by its id; `PanelAnswer.reply(value)`,
    what a web panel's `window.vitruvian.call` gets back. On an app that has
    `Feature.OPEN_SETTINGS`, `open` may name the tool's settings panel, and the
    app opens Settings on the tool's detail."""

    result: Dict[str, Any]
    """The answer as the wire carries it."""

    @classmethod
    def page(cls, tree: UITree) -> "PanelAnswer":
        return cls({"tree": tree.to_json()})

    @classmethod
    def keep(cls) -> "PanelAnswer":
        return cls({"keep": True})

    @classmethod
    def open(cls, panel: str) -> "PanelAnswer":
        return cls({"open": panel})

    @classmethod
    def reply(cls, value: Any) -> "PanelAnswer":
        return cls({"reply": value})


Opened = Callable[["App", "Panel"], Optional[UITree]]
"""Gives the first page when the person opens the panel; a web panel gives none."""
Acted = Callable[["App", "Panel", PanelEvent], PanelAnswer]
"""Answers what the person did."""
Called = Callable[["App", str, Any], Any]
"""A web panel's call of a method of the tool's own, one whose name starts with
`tool/`: the method, its params, and the reply."""

TOOLS_OWN = "tool/"
"""A method of the tool's own, which a web page may call: its name starts with this."""


class Panel:
    """One of the tool's panels, as the manifest declares it. Made by
    `tool.panel(id, on_open=..., on_event=...)`. Use it from the thread that
    runs the tool, as everything of a Tool."""

    def __init__(self, id: str, tool: "Tool", on_open: Opened, on_event: Acted) -> None:
        self.id = id
        """The id the manifest gives it."""
        self.on_call: Optional[Called] = None
        """For a web panel: what its page's calls of the tool's own methods
        answer. With none, such a call is answered as a method not found. A
        call of a request the app does, such as notify/hud, is passed to the
        app as the tool's own, with no handler."""
        self._tool = tool
        self._on_open = on_open
        self._on_event = on_event
        self._is_open = False

    @property
    def is_open(self) -> bool:
        """True while the app has it open: from ui/open to ui/close."""
        return self._is_open

    def render(self, tree: UITree) -> bool:
        """Sends a new page for the panel, unprompted: ui/render. False, and
        nothing is sent, when the panel is not open. The app draws at most
        four pages a second for a panel; send fewer."""
        if not self._is_open:
            return False
        return self._tool._note(
            "ui/render", UIRenderParams(panel=self.id, tree=tree).to_json()
        )

    def badge(self, count: Optional[int] = None, dot: bool = False) -> None:
        """Puts a count, or a dot, beside the tool's page in the island's Explore gallery:
        ui/badge. With neither, the badge goes. Needs notify in uses. Raises
        a Refusal when the app refuses it."""
        self._tool._app.ui.badge(count=count, dot=True if dot else None)


# Writing a page: one function for each kind of block, and `tree` of them.


def text(
    text: UIText, style: Optional[str] = None, lines: Optional[int] = None
) -> UIBlock:
    """Words. `style` is body, secondary, caption or monospaced; `lines` the most lines they take."""
    return UIBlock("text", TextBlock(text=text, style=style, lines=lines))


def heading(text: UIText, section: Optional[bool] = None) -> UIBlock:
    """A heading, of two lines at most. With `section=True` it starts a
    section of the page, which the app may list for the person to jump to;
    one without is a sub-heading. An app without `Feature.SECTIONS` draws a
    plain heading, and the conformance script's older app fails a page that
    sends it one, so ask `app.supports(Feature.SECTIONS)` first."""
    return UIBlock("heading", HeadingBlock(text=text, section=section))


def row(
    title: UIText,
    id: Optional[str] = None,
    subtitle: Optional[UIText] = None,
    icon: Optional[str] = None,
    trailing: Optional[UIText] = None,
) -> UIBlock:
    """A row. With an `id` it can be tapped."""
    return UIBlock(
        "row",
        RowBlock(title=title, subtitle=subtitle, icon=icon, trailing=trailing),
        id=id,
    )


def button(
    id: str, title: UIText, style: Optional[str] = None, enabled: Optional[bool] = None
) -> UIBlock:
    """A button. Pressing it is the event tap. `style` is plain, prominent or destructive."""
    return UIBlock(
        "button", ButtonBlock(title=title, style=style, enabled=enabled), id=id
    )


def toggle(
    id: str,
    title: UIText,
    is_on: bool,
    enabled: Optional[bool] = None,
    help: Optional[UIText] = None,
) -> UIBlock:
    """A switch. Turning it is the event toggle, with its new state. `help`
    is a line or two under it that says what it does; an app without
    `Feature.SECTIONS` leaves it out, so send that app a `text` after the
    switch instead."""
    return UIBlock(
        "toggle",
        ToggleBlock(title=title, value=is_on, enabled=enabled, help=help),
        id=id,
    )


def field(
    id: str,
    title: Optional[UIText] = None,
    value: Optional[str] = None,
    placeholder: Optional[UIText] = None,
    kind: Optional[str] = None,
    help: Optional[UIText] = None,
) -> UIBlock:
    """A field to type in. Return is the event submit; leaving it changed is
    the event change. `kind` is text, number or secret. `help` is as a
    switch's."""
    return UIBlock(
        "field",
        FieldBlock(
            title=title, value=value, placeholder=placeholder, kind=kind, help=help
        ),
        id=id,
    )


def list_(id: str, rows: List[UIListRow]) -> UIBlock:
    """Rows, drawn together. Tapping one is the event tap, with the row's id.
    Named with an underscore, as Python's own `list` is a word already."""
    return UIBlock("list", ListBlock(rows=rows), id=id)


def progress(value: Optional[float] = None, label: Optional[UIText] = None) -> UIBlock:
    """How far something has got: `value` from 0 to 1, or none when nobody knows."""
    return UIBlock("progress", ProgressBlock(value=value, label=label))


def image(
    source: str, alt: Optional[UIText] = None, height: Optional[float] = None
) -> UIBlock:
    """A picture: a path inside the tool's folder, or a data: PNG or JPEG."""
    return UIBlock("image", ImageBlock(source=source, alt=alt, height=height))


def divider() -> UIBlock:
    """A line between blocks."""
    return UIBlock("divider", DividerBlock())


def link(title: UIText, url: str) -> UIBlock:
    """A link the app opens through its open service."""
    return UIBlock("link", LinkBlock(title=title, url=url))


def spacer(size: Optional[float] = None) -> UIBlock:
    """Room between blocks, in points; 8 when left out."""
    return UIBlock("spacer", SpacerBlock(size=size))


def choice(
    id: str,
    value: str,
    options: List[UIChoiceOption],
    title: Optional[UIText] = None,
    enabled: Optional[bool] = None,
    fallback: Optional[UIText] = None,
    help: Optional[UIText] = None,
) -> UIBlock:
    """A pop-up menu: one of a fixed list of options, each a
    `UIChoiceOption(value=..., title=...)`. `value` is the selected option's.
    Picking one is the event change, read with `event.text`.

    An app before 3.48 does not know this kind and draws `fallback`, which
    nobody can change. So ask `app.supports(Feature.CHOICE)` first, and send
    a `field` to an app without it. With no `fallback` given, one is written:
    the title, a colon and the selected option's title. `help` is as a
    switch's."""
    return UIBlock(
        "choice",
        ChoiceBlock(
            value=value, options=options, title=title, enabled=enabled, help=help
        ),
        id=id,
        fallback=_said_plainly(title, value, options) if fallback is None else fallback,
    )


def chips(
    id: str,
    options: List[UIChipOption],
    title: Optional[UIText] = None,
    enabled: Optional[bool] = None,
    help: Optional[UIText] = None,
    fallback: Optional[UIText] = None,
) -> UIBlock:
    """Chips: a fixed list of options, each a
    `UIChipOption(value=..., title=..., on=...)`, any number of them on at
    once. Turning one is the event change, read with `event.values`: the
    values of every option then on. An option with `enabled=False` is dimmed,
    and its `reason` says why.

    An app without `Feature.CHIPS` does not know this kind and draws
    `fallback`, which nobody can change. So ask `app.supports(Feature.CHIPS)`
    first, and send a `toggle` for each option to an app without it. With no
    `fallback` given, one is written: the title, a colon and the titles of
    the options that are on. `help` is as a switch's."""
    return UIBlock(
        "chips",
        ChipsBlock(options=options, title=title, enabled=enabled, help=help),
        id=id,
        fallback=(
            _listed_plainly(title, [option.title for option in options if option.on])
            if fallback is None
            else fallback
        ),
    )


def _words(text: UIText, language: str) -> str:
    """A text in a language: its own entry, else English; a string whatever
    the language."""
    if isinstance(text, str):
        return text
    return text.get(language, text.get("en", ""))


def _languages(texts: List[UIText]) -> List[str]:
    """The languages any of these texts has, in order."""
    return sorted(
        {language for text in texts if not isinstance(text, str) for language in text}
    )


def _listed_plainly(title: Optional[UIText], on: List[UIText]) -> UIText:
    """What chips say, as words: the title, a colon and the titles of the
    options that are on, or those titles alone, in every language any of them
    has. A dash stands for none."""

    def said(language: str) -> str:
        titles = ", ".join(_words(text, language) for text in on) if on else "\u2014"
        return titles if title is None else f"{_words(title, language)}: {titles}"

    languages = _languages(on if title is None else [title, *on])
    if not languages:
        return said("en")
    return {language: said(language) for language in languages}


def _said_plainly(
    title: Optional[UIText], value: str, options: List[UIChoiceOption]
) -> UIText:
    """What a choice says, as words: the title, a colon and the selected
    option's title, or that title alone, in every language either has. A
    value that is no option's is written as it is."""
    selected: UIText = next(
        (option.title for option in options if option.value == value), value
    )
    if title is None:
        return selected
    languages = _languages([title, selected])
    if not languages:
        return f"{_words(title, 'en')}: {_words(selected, 'en')}"
    return {
        language: f"{_words(title, language)}: {_words(selected, language)}"
        for language in languages
    }


def tree(*blocks: Optional[UIBlock]) -> UITree:
    """A page as the blocks it holds, one under the other. A block that is
    None is left out, so a page may be written with
    `text("That is a lot") if count > 9 else None`:

        tree(
            heading("Counter"),
            text(f"Pressed {count} times"),
            button("add", "Add one", style="prominent"),
            text("That is a lot", style="caption") if count > 9 else None,
        )
    """
    return UITree(blocks=[block for block in blocks if block is not None])
