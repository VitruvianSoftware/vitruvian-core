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
from typing import Any, Callable, Dict, List, Optional

from .generated.messages import (
    CommandRunParams,
    InitializeParams,
    LanguageChangedParams,
    PreferencesChangedParams,
    RPCErrorObject,
    ShapeError,
)
from .generated.methods import PROTOCOL_VERSION, AppCalls
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
        self._handlers: Dict[str, Handler] = {}
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
        # A result or a failure here is an answer nobody waits for: it came
        # after its call gave up.

    def _greet(self, id: RPCID, params: Any) -> None:
        hello = _try(lambda: InitializeParams.from_json(params))
        if hello is None:
            return self._refuse(id, RPCErrorCode.INVALID_PARAMS, "invalid params")
        if PROTOCOL_VERSION not in hello.protocol_versions:
            return self._refuse(
                id,
                RPCErrorCode.INVALID_PARAMS,
                f"this tool speaks protocol {PROTOCOL_VERSION} only",
            )
        self.language = hello.language
        self.data_folder = hello.data_folder
        self._greeted = True
        self._wire.send(
            Result(
                id, {"protocolVersion": PROTOCOL_VERSION, "toolVersion": self.version}
            )
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

    def _note(self, method: str, params: Dict[str, Any]) -> None:
        if not self._greeted or self._stopping:
            return
        self._wire.send(Notice(method, params))


def _try(read: Callable[[], Any]) -> Any:
    try:
        return read()
    except ShapeError:
        return None
