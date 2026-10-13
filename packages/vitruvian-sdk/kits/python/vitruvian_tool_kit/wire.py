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
"""The link to the app, from the tool's end: messages read from one file
descriptor and written to another, a line each.

It is used from one thread. Reading waits, with `select`, until a message has
come, the link has ended, or the time given has passed. It never waits longer
than it is told to.
"""

from __future__ import annotations

import errno
import json
import os
import select
import time
from typing import Any, Dict, List, Optional, Union

from .generated.messages import RPCErrorObject, ShapeError

MAX_LINE_BYTES = 1_048_576
"""The longest line either side may write, not counting its line break."""

RPCID = Union[int, str]


class Request:
    def __init__(
        self, id: RPCID, method: str, params: Optional[Dict[str, Any]] = None
    ) -> None:
        self.id, self.method, self.params = id, method, params

    def to_json(self) -> Dict[str, Any]:
        out: Dict[str, Any] = {"jsonrpc": "2.0", "id": self.id, "method": self.method}
        if self.params is not None:
            out["params"] = self.params
        return out


class Notice:
    def __init__(self, method: str, params: Optional[Dict[str, Any]] = None) -> None:
        self.method, self.params = method, params

    def to_json(self) -> Dict[str, Any]:
        out: Dict[str, Any] = {"jsonrpc": "2.0", "method": self.method}
        if self.params is not None:
            out["params"] = self.params
        return out


class Result:
    def __init__(self, id: RPCID, result: Any) -> None:
        self.id, self.result = id, result

    def to_json(self) -> Dict[str, Any]:
        return {"jsonrpc": "2.0", "id": self.id, "result": self.result}


class Failure:
    def __init__(self, id: Optional[RPCID], error: RPCErrorObject) -> None:
        self.id, self.error = id, error

    def to_json(self) -> Dict[str, Any]:
        return {"jsonrpc": "2.0", "id": self.id, "error": self.error.to_json()}


Message = Union[Request, Notice, Result, Failure]
"""One JSON-RPC 2.0 message: what one line on the link holds."""


def _is_id(value: Any) -> bool:
    return isinstance(value, str) or (
        isinstance(value, int) and not isinstance(value, bool)
    )


def message_of(line: Union[str, bytes]) -> Optional[Message]:
    """The message a line holds, by the same rules as the Swift kit; None when it holds none."""
    try:
        value = json.loads(line)
    except ValueError:
        return None
    if not isinstance(value, dict) or value.get("jsonrpc") != "2.0":
        return None
    if "method" in value:
        if (
            "result" in value
            or "error" in value
            or not isinstance(value["method"], str)
        ):
            return None
        params = value.get("params")
        if params is not None and not isinstance(params, dict):
            return None
        if "id" not in value:
            return Notice(value["method"], params)
        return (
            Request(value["id"], value["method"], params)
            if _is_id(value["id"])
            else None
        )
    if "error" in value:
        if (
            "result" in value
            or "id" not in value
            or not (value["id"] is None or _is_id(value["id"]))
        ):
            return None
        try:
            return Failure(value["id"], RPCErrorObject.from_json(value["error"]))
        except ShapeError:
            return None
    if not _is_id(value.get("id")) or "result" not in value:
        return None
    return Result(value["id"], value["result"])


def line_of(message: Message) -> bytes:
    """A message as one line, with its line break."""
    return (
        json.dumps(message.to_json(), separators=(",", ":"), ensure_ascii=False) + "\n"
    ).encode("utf-8")


class Wire:
    """Reads and writes the link, one message per line, on the calling thread."""

    def __init__(self, input: int, output: int) -> None:
        self._input = input
        self._output = output
        self._pending = b""
        self._discarding = False
        self._lines: List[bytes] = []
        self.ended = False

    def next(self, deadline: Optional[float]) -> Union[Message, str]:
        """The next message, or "ended", or "late" once `deadline` (on time.monotonic) has passed.

        A line that is not a message, and a line over 1 MB, are dropped: there
        is no request to answer.
        """
        while True:
            while self._lines:
                message = message_of(self._lines.pop(0))
                if message is not None:
                    return message
            if self.ended:
                return "ended"
            wait = None
            if deadline is not None:
                wait = deadline - time.monotonic()
                if wait <= 0:
                    return "late"
            try:
                ready, _, _ = select.select([self._input], [], [], wait)
            except InterruptedError:
                continue
            except (OSError, ValueError):
                self.ended = True
                continue
            if not ready:
                continue
            try:
                chunk = os.read(self._input, 65_536)
            except InterruptedError:
                continue
            except BlockingIOError:
                continue
            except OSError:
                self.ended = True
                continue
            if not chunk:
                self.ended = True
                continue
            self._split(chunk)

    def _split(self, chunk: bytes) -> None:
        """Cuts bytes into lines, as the protocol's LineSplitter does."""
        rest = chunk
        while True:
            at = rest.find(b"\n")
            if at < 0:
                break
            head, rest = rest[:at], rest[at + 1 :]
            if self._discarding:
                self._discarding = False
            elif len(self._pending) + len(head) <= MAX_LINE_BYTES:
                line = self._pending + head
                if line.strip():
                    self._lines.append(line)
            self._pending = b""
        if self._discarding:
            return
        if len(self._pending) + len(rest) > MAX_LINE_BYTES:
            self._discarding = True
            self._pending = b""
            return
        self._pending += rest

    def send(self, message: Message) -> bool:
        """Writes one message as one line. False when it could not be; the link has then ended."""
        if self.ended:
            return False
        data = line_of(message)
        while data:
            try:
                written = os.write(self._output, data)
            except InterruptedError:
                continue
            except BlockingIOError:
                select.select([], [self._output], [], 1)
                continue
            except OSError as error:
                if error.errno in (errno.EAGAIN, errno.EINTR):
                    continue
                self.ended = True
                return False
            data = data[written:]
        return True
