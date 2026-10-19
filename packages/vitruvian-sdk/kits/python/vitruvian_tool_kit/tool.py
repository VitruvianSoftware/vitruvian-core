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
"""A tool that runs as its own program: its commands, and the loop that reads
what the app sends and answers it. The Swift kit's Tool, in Python."""

from __future__ import annotations

import inspect
import os
import signal
import sys
import time
from datetime import datetime
from typing import Any, Callable, Dict, FrozenSet, List, Optional

from .generated.messages import (
    PROTOCOL_VERSIONS,
    CommandRunParams,
    InitializeParams,
    LanguageChangedParams,
    PreferencesChangedParams,
    RPCErrorObject,
    ShapeError,
    StatusState,
    UICloseParams,
    UIEventParams,
    UIOpenParams,
    UIText,
)
from .generated.methods import METHODS, AppCalls
from .panels import TOOLS_OWN, Acted, Opened, Panel, PanelAnswer, PanelEvent
from .wire import Failure, Message, Notice, Request, Result, RPCID, Wire


class RPCErrorCode:
    """JSON-RPC's own failure codes."""

    PARSE_ERROR = -32700
    INVALID_REQUEST = -32600
    METHOD_NOT_FOUND = -32601
    INVALID_PARAMS = -32602
    INTERNAL_ERROR = -32603


class RefusalCode:
    """Why a request was refused, as the code of its failure."""

    NOT_IN_USES = -32001
    """The app: the service is not listed in the tool's `uses`."""
    NOT_INSTALLED = -32002
    """The app: the tool is not installed."""
    PERMISSION_MISSING = -32003
    """The app: Vitruvian lacks a macOS permission the service needs."""
    UNAVAILABLE = -32004
    """The app: not available right now."""
    COMMAND_REFUSED = -32010
    """The tool: it would not run the command."""


class Feature:
    """What an app may have beyond the first release of a protocol version, by
    the name it gives at hello. Ask with `app.supports(Feature.CHOICE)`."""

    STATUS = "ui.status"
    """`ui/status`: the tool's status on the closed island."""
    CHOICE = "ui.choice"
    """The `choice` block."""
    PREFERENCE_OPTIONS = "preferences.options"
    """`options` on a text preference, drawn as a pop-up menu."""
    STATUS_ACTIVITY = "ui.status.activity"
    """`activity` and `since` on `ui/status`: a few words, or a count of
    seconds, beside the mark. From 3.50."""
    OPEN_SETTINGS = "ui.open.settings"
    """`open(panel)` may name the tool's own settings panel: the app opens
    Settings on the tool's detail. From 3.58."""
    CHIPS = "ui.chips"
    """The `chips` block."""
    SECTIONS = "ui.sections"
    """`section` on a heading, and `help` on a switch, a field, a choice and
    chips."""


class CommandRefused(Exception):
    """A command that will not run. Raise it from a handler; the app is answered with -32010 and the message."""


class Refusal(Exception):
    """The app answered a call with a failure. `code` says why; RefusalCode names the refusals."""

    def __init__(self, error: RPCErrorObject) -> None:
        super().__init__(error.message)
        self.error = error

    @property
    def code(self) -> int:
        return self.error.code

    @property
    def data(self) -> Any:
        return self.error.data


class AppUnreachable(Exception):
    """A call to the app that got no answer.

    reason is "link_closed" (the app said goodbye or closed the link, or has
    not said hello) or "no_answer" (no answer within `seconds`).
    """

    def __init__(self, reason: str, seconds: Optional[float] = None) -> None:
        super().__init__(
            "the link to the app is closed"
            if reason == "link_closed"
            else f"no answer within {seconds} seconds"
        )
        self.reason = reason
        self.seconds = seconds


class App(AppCalls):
    """The app, as a handler sees it: one call per message a tool may send, by
    its name (`app.notify.hud(icon=..., message=...)`,
    `app.storage.get(key=...)`), and what the app said at hello. Any call can be
    refused: it then raises a Refusal. A handler that lets it through has its
    command answered as refused."""

    def __init__(self, tool: "Tool") -> None:
        super().__init__(tool._call, tool._note)
        self._tool = tool

    @property
    def language(self) -> str:
        """The language the app is in, as a tag such as en-US."""
        return self._tool.language

    @property
    def data_folder(self) -> str:
        """The folder the tool may keep its own files in; also the folder it is started in."""
        return self._tool.data_folder

    def supports(self, feature: str) -> bool:
        """Whether this app has something a later release added to the
        protocol version: it named it at hello. `Feature` holds the names.
        False for an app that named nothing, as every app before 3.48 does.
        Ask before using a `choice` block, and send a `field` to an app
        without it; before `chips`, and send a `toggle` for each option to
        an app without `Feature.CHIPS`; and before a heading's `section` or a
        control's `help`, which an app without `Feature.SECTIONS` does not
        draw."""
        return feature in self._tool.features

    def status(
        self,
        state: StatusState,
        text: Optional[UIText] = None,
        icon: Optional[str] = None,
        activity: Optional[UIText] = None,
        since: Optional[datetime] = None,
    ) -> bool:
        """Sets the tool's status, a small mark the app draws on the closed
        island: ui/status. `state` is none, ok, busy, attention or failure.
        Each one replaces the last; "none" takes it away; and it goes when the
        tool's program ends, so a tool that wants it to last starts with the
        app ("activation": ["onLaunch"]). `text` says what it means, for
        VoiceOver. `icon`, an SF Symbol name, replaces the state's own glyph.
        The manifest must declare contributes.status: without it the app
        refuses, and this raises the Refusal. It needs nothing in uses.

        `activity`, a few words, and `since`, a start time the app counts the
        seconds from, are drawn beside the mark while it is the one the closed
        island shows; the words win over the start time. Six characters or
        fewer, and a number is best. They show only on an app that has
        ui.status.activity (3.50 and later): to an app without it the status
        is sent without them. The manifest's status must say
        "activity": true, or the app leaves them out. A naive `since` is read
        as local time.

        False, and nothing is sent, when the app did not say it has
        ui.status: an app before 3.48 shows no status. True when it was sent
        and answered; the person may still have switched the mark off.

        `app.ui.status(...)` is the bare request: it is sent whatever the app
        said, and an older app answers it with a Refusal, -32601."""
        if not self.supports(Feature.STATUS):
            return False
        if not self.supports(Feature.STATUS_ACTIVITY):
            # An app from before 3.50 is sent the status without its words.
            activity, since = None, None
        self.ui.status(
            state=state,
            text=text,
            icon=icon,
            activity=activity,
            since=None if since is None else since.timestamp(),
        )
        return True


Handler = Callable[[App], Any]


class Tool:
    """A tool's commands, and the loop that answers the app.

        tool = Tool(version="0.1.0")

        @tool.command("hello")
        def hello(app):
            app.notify.hud(icon="hand.wave", message="Hello")

        tool.run()

    It works on one thread, the one that calls run(). A handler runs on it, and
    a call to the app made inside a handler reads the link until the answer has
    come. Nothing here starts a thread. What the app sends while a handler
    waits is kept and handled after the handler returns. A handler must not be
    `async`: the command would be answered before its work was done, so one is
    refused.
    """

    def __init__(self, version: str, input: int = 0, output: int = 1) -> None:
        self.version = version
        self.answer_seconds = 10.0
        """How long a call to the app waits for its answer, in seconds."""
        self.on_start: Optional[Callable[[App], None]] = None
        """Called once, after the app has said hello and been answered."""
        self.on_preferences_changed: Optional[Callable[[App, Dict[str, Any]], None]] = (
            None
        )
        """Called when the person changed a preference: each one's id and value."""
        self.on_language_changed: Optional[Callable[[App], None]] = None
        """Called when the person changed the app's language."""
        self.language = "en"
        self.data_folder = os.getcwd()
        self.features: FrozenSet[str] = frozenset()
        """What the app said it has beyond the first release of the protocol
        version, by name: the hello's `features`. Empty for an app that said
        nothing, which is every app before 3.48. Ask with `app.supports`."""
        self._handlers: Dict[str, Handler] = {}
        self._panels: Dict[str, Panel] = {}
        self._wire = Wire(input, output)
        self._app = App(self)
        self._last_id = 0
        self._kept: List[Message] = []
        self._greeted = False
        self._stopping = False

    def command(self, id: str, handler: Optional[Handler] = None) -> Any:
        """Says what a command does. `id` is the one the manifest gives it.

        Use it as `tool.command("hello", hello)`, or as a decorator,
        `@tool.command("hello")`.
        """
        if handler is None:

            def decorate(function: Handler) -> Handler:
                self._handlers[id] = function
                return function

            return decorate
        self._handlers[id] = handler
        return self

    def panel(
        self,
        id: str,
        on_open: Opened,
        on_event: Optional[Acted] = None,
    ) -> Panel:
        """Says what a panel does. `id` is the one the manifest gives it.
        `on_open` gives the first page when the person opens it; a web panel
        gives none. `on_event` answers what the person did. The handle it
        gives back sends pages unprompted and sets the tool's badge."""
        panel = Panel(
            id,
            self,
            on_open,
            on_event or (lambda app, panel, event: PanelAnswer.keep()),
        )
        self._panels[id] = panel
        return panel

    def run(self) -> None:
        """Reads and answers until the app says goodbye, then exits with 0."""
        sys.exit(self.serve())

    def serve(self) -> int:
        """Reads and answers until the app says goodbye or the link ends. Returns 0, the status to exit with."""
        # A link that has gone is seen as a failed write, not as a signal.
        signal.signal(signal.SIGPIPE, signal.SIG_IGN)
        while not self._stopping:
            if self._kept:
                self._handle(self._kept.pop(0))
                continue
            next = self._wire.next(None)
            if isinstance(next, str):
                self._stopping = True
            else:
                self._handle(next)
        return 0

    def _handle(self, message: Message) -> None:
        if isinstance(message, Request):
            if message.method == "initialize":
                return self._greet(message.id, message.params)
            if message.method == "command/run":
                return self._run_command(message.id, message.params)
            if message.method == "ui/open":
                return self._open_panel(message.id, message.params)
            if message.method == "ui/event":
                return self._panel_event(message.id, message.params)
            return self._refuse(
                message.id, RPCErrorCode.METHOD_NOT_FOUND, "method not found"
            )
        if isinstance(message, Notice):
            if message.method == "shutdown":
                self._stopping = True
            elif message.method == "preferences/changed":
                changed = _try(
                    lambda: PreferencesChangedParams.from_json(message.params)
                )
                if changed is not None and self.on_preferences_changed is not None:
                    self.on_preferences_changed(self._app, changed.values)
            elif message.method == "language/changed":
                changed = _try(lambda: LanguageChangedParams.from_json(message.params))
                if changed is not None:
                    self.language = changed.language
                    if self.on_language_changed is not None:
                        self.on_language_changed(self._app)
            elif message.method == "ui/close":
                closed = _try(lambda: UICloseParams.from_json(message.params))
                if closed is not None and closed.panel in self._panels:
                    self._panels[closed.panel]._is_open = False
        # A result or a failure here is an answer nobody waits for: it came
        # after its call gave up.

    def _greet(self, id: RPCID, params: Any) -> None:
        hello = _try(lambda: InitializeParams.from_json(params))
        if hello is None:
            return self._refuse(id, RPCErrorCode.INVALID_PARAMS, "invalid params")
        # The newest version both speak. Version 2 only adds to version 1,
        # so a tool of either is answered by an app of either.
        picked = next(
            (v for v in reversed(PROTOCOL_VERSIONS) if v in hello.protocol_versions),
            None,
        )
        if picked is None:
            return self._refuse(
                id,
                RPCErrorCode.INVALID_PARAMS,
                f"this tool speaks protocols {' and '.join(PROTOCOL_VERSIONS)} only",
            )
        self.language = hello.language
        self.data_folder = hello.data_folder
        self.features = frozenset(hello.features or [])
        self._greeted = True
        self._wire.send(
            Result(id, {"protocolVersion": picked, "toolVersion": self.version})
        )
        if self.on_start is not None:
            self.on_start(self._app)

    def _run_command(self, id: RPCID, params: Any) -> None:
        if not self._greeted:
            return self._refuse(
                id, RPCErrorCode.INVALID_REQUEST, "initialize comes first"
            )
        asked = _try(lambda: CommandRunParams.from_json(params))
        if asked is None:
            return self._refuse(id, RPCErrorCode.INVALID_PARAMS, "invalid params")
        handler = self._handlers.get(asked.command)
        if handler is None:
            return self._refuse(id, RPCErrorCode.INVALID_PARAMS, "no such command")
        try:
            returned = handler(self._app)
            if inspect.isawaitable(returned):
                if inspect.iscoroutine(returned):
                    returned.close()
                return self._refuse(
                    id,
                    RefusalCode.COMMAND_REFUSED,
                    "the handler is async; the kit runs handlers to their end",
                )
            self._wire.send(Result(id, {}))
        except CommandRefused as refused:
            self._refuse(id, RefusalCode.COMMAND_REFUSED, str(refused))
        except Refusal as refusal:
            # The app refused something the command needed. Its reason goes
            # with ours, for the log.
            self._refuse(
                id,
                RefusalCode.COMMAND_REFUSED,
                "command refused",
                refusal.error.to_json(),
            )
        except Exception as error:  # noqa: BLE001 - any failure is the command's refusal, as in Swift
            self._refuse(
                id, RefusalCode.COMMAND_REFUSED, str(error) or type(error).__name__
            )

    def _open_panel(self, id: RPCID, params: Any) -> None:
        asked = _try(lambda: UIOpenParams.from_json(params))
        if asked is None:
            return self._refuse(id, RPCErrorCode.INVALID_PARAMS, "invalid params")
        panel = self._panels.get(asked.panel)
        if panel is None:
            return self._refuse(id, RPCErrorCode.INVALID_PARAMS, "no such panel")
        panel._is_open = True

        def give() -> Dict[str, Any]:
            tree = panel._on_open(self._app, panel)
            return {} if tree is None else {"tree": tree.to_json()}

        self._answering(id, give)

    def _panel_event(self, id: RPCID, params: Any) -> None:
        asked = _try(lambda: UIEventParams.from_json(params))
        if asked is None:
            return self._refuse(id, RPCErrorCode.INVALID_PARAMS, "invalid params")
        panel = self._panels.get(asked.panel)
        if panel is None or not panel.is_open:
            return self._refuse(
                id, RPCErrorCode.INVALID_PARAMS, "the panel is not open"
            )

        def give() -> Dict[str, Any]:
            if asked.event == "bridge":
                return {"reply": self._bridge(asked.value, panel)}
            event = PanelEvent(asked.block, asked.event, asked.value)
            return panel._on_event(self._app, panel, event).result

        self._answering(id, give)

    def _bridge(self, value: Any, panel: Panel) -> Any:
        """A web panel's call: a request the app does is passed to the app as
        the tool's own, under the tool's uses; a method of the tool's own
        goes to the panel's on_call."""
        if not isinstance(value, dict) or not isinstance(value.get("method"), str):
            raise Refusal(
                RPCErrorObject(
                    code=RPCErrorCode.INVALID_PARAMS, message="invalid params"
                )
            )
        method, params = value["method"], value.get("params")
        if method.startswith(TOOLS_OWN):
            if panel.on_call is None:
                raise Refusal(
                    RPCErrorObject(
                        code=RPCErrorCode.METHOD_NOT_FOUND, message="method not found"
                    )
                )
            return panel.on_call(self._app, method, params)
        row = next((m for m in METHODS if m.method == method), None)
        if row is None or row.sender != "tool" or row.kind != "request":
            raise Refusal(
                RPCErrorObject(
                    code=RPCErrorCode.METHOD_NOT_FOUND, message="method not found"
                )
            )
        return self._call(method, params if isinstance(params, dict) else {})

    def _answering(self, id: RPCID, give: Callable[[], Dict[str, Any]]) -> None:
        """Answers a request with what `give` returns, or with the refusal or
        error it raises."""
        try:
            self._wire.send(Result(id, give()))
        except Refusal as refusal:
            self._refuse(id, refusal.code, str(refusal), refusal.data)
        except Exception as error:  # noqa: BLE001 - any failure is the answer, as in Swift
            self._refuse(
                id, RPCErrorCode.INTERNAL_ERROR, str(error) or type(error).__name__
            )

    def _refuse(self, id: RPCID, code: int, message: str, data: Any = None) -> None:
        self._wire.send(
            Failure(id, RPCErrorObject(code=code, message=message, data=data))
        )

    def _call(self, method: str, params: Optional[Dict[str, Any]]) -> Any:
        """Sends a request and reads the link until its answer has come."""
        if not self._greeted or self._stopping:
            raise AppUnreachable("link_closed")
        self._last_id += 1
        id = self._last_id
        if not self._wire.send(Request(id, method, params)):
            self._stopping = True
            raise AppUnreachable("link_closed")
        deadline = time.monotonic() + self.answer_seconds
        while True:
            next = self._wire.next(deadline)
            if next == "ended":
                self._stopping = True
                raise AppUnreachable("link_closed")
            if next == "late":
                raise AppUnreachable("no_answer", self.answer_seconds)
            if isinstance(next, Result) and next.id == id:
                return next.result
            if isinstance(next, Failure) and next.id == id:
                raise Refusal(next.error)
            if isinstance(next, Notice) and next.method == "shutdown":
                self._stopping = True
                raise AppUnreachable("link_closed")
            self._kept.append(next)

    def _note(self, method: str, params: Dict[str, Any]) -> bool:
        """Sends a notice. False when the link is not open."""
        if not self._greeted or self._stopping:
            return False
        return self._wire.send(Notice(method, params))


def _try(read: Callable[[], Any]) -> Any:
    try:
        return read()
    except ShapeError:
        return None
