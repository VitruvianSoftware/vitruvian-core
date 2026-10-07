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

import asyncio
from typing import Any

import pytest

from vitruvian_roborock.core import config
from vitruvian_roborock.core.device import DeviceError, UnknownActionError

USER_DATA = {
    "rriot": {"u": "user", "s": "secret", "h": "hmac", "k": "key", "r": {"r": "US", "a": "https://a", "m": "ssl://m", "l": "https://l"}},
    "uid": 1,
    "token": "tok",
    "rruid": "rr1",
    "region": "us",
    "countrycode": "1",
    "country": "US",
    "nickname": "tester",
}

STATUS = {
    "device": {"id": "duid-1", "name": "Rocky", "model": "roborock.vacuum.a70", "local": True},
    "state": "charging",
    "state_code": 8,
    "battery": 100,
    "error": None,
    "in_cleaning": False,
    "in_returning": False,
    "rooms": [{"id": 16, "name": "Kitchen"}, {"id": 17, "name": "Living Room"}],
}

PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 16


@pytest.fixture(autouse=True)
def isolated_home(tmp_path, monkeypatch):
    """Point every path at a temp dir so no test can read or write a real login."""
    home = tmp_path / "home"
    home.mkdir()
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.delenv("XDG_CONFIG_HOME", raising=False)
    monkeypatch.delenv(config.HOME_ENV, raising=False)
    monkeypatch.delenv(config.PORT_ENV, raising=False)
    return home


@pytest.fixture
def logged_in():
    credentials = config.Credentials(email="me@example.com", user_data=dict(USER_DATA))
    config.save_credentials(credentials)
    return credentials


class FakeVacuum:
    """Stands in for RoborockVacuum: records what it was asked and fails on demand."""

    def __init__(self) -> None:
        self.snapshot: dict[str, Any] = dict(STATUS)
        self.png: bytes | None = PNG
        self.commands: list[tuple[str, dict[str, Any] | None]] = []
        self.connects = 0
        self.closed = 0
        self.fail_connect = 0
        self.fail_status = False
        self.credentials_rejected = False
        self.listener = None
        self.polled = asyncio.Event()

    async def connect(self) -> None:
        self.connects += 1
        if self.fail_connect:
            self.fail_connect -= 1
            raise DeviceError("cloud unreachable")

    async def close(self) -> None:
        self.closed += 1

    async def status(self) -> dict[str, Any]:
        self.polled.set()
        if self.fail_status:
            raise DeviceError("no answer")
        return dict(self.snapshot)

    async def map_png(self) -> bytes | None:
        return self.png

    async def command(self, action: str, params: dict[str, Any] | None = None) -> Any:
        if action == "bogus":
            raise UnknownActionError("Unknown action 'bogus'.")
        if action == "wash_start":
            raise DeviceError("The vacuum refused 'wash_start': unsupported")
        self.commands.append((action, params))
        return ["ok"]

    def on_update(self, callback) -> None:
        self.listener = callback


@pytest.fixture
def vacuum():
    return FakeVacuum()


async def until(predicate, timeout: float = 2.0) -> None:
    """Wait for the service loop to reach a state, without sleeping a fixed time."""
    deadline = asyncio.get_running_loop().time() + timeout
    while not predicate():
        if asyncio.get_running_loop().time() > deadline:
            raise AssertionError("condition not reached in time")
        await asyncio.sleep(0.005)
