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

"""What the daemon knows about the vacuum, and the loop that keeps it current.

`StateStore` holds the latest status and map and fans changes out to SSE
subscribers. `VacuumService` owns the one connection to the vacuum: it connects,
polls, reconnects with backoff, and is the only thing that sends commands.
"""

from __future__ import annotations

import asyncio
import contextlib
import hashlib
import logging
import os
import time
from collections.abc import Callable
from typing import Any

from vitruvian_roborock.core import auth, config
from vitruvian_roborock.core.device import DeviceError, RoborockVacuum, Vacuum

_LOGGER = logging.getLogger(__name__)

Event = tuple[str, dict[str, Any]]
VacuumFactory = Callable[[config.Credentials], Vacuum]

# Roborock state codes in which the robot is parked: sleeping, idle, charging, fully charged.
_PARKED_STATES = frozenset({2, 3, 8, 100})

_SUBSCRIBER_BACKLOG = 32


class ServiceUnavailable(Exception):
    """A command arrived while there is no usable connection to the vacuum."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


class StateStore:
    def __init__(self) -> None:
        self._status: dict[str, Any] = {"authenticated": False, "connected": False, "map_version": 0}
        self._map: bytes | None = None
        self._map_digest: str | None = None
        self._map_version = 0
        self._subscribers: set[asyncio.Queue[Event | None]] = set()

    @property
    def status(self) -> dict[str, Any]:
        return self._status

    @property
    def map_png(self) -> bytes | None:
        return self._map

    @property
    def map_version(self) -> int:
        return self._map_version

    def set_status(self, status: dict[str, Any]) -> bool:
        """Store a new status. Subscribers hear about it only if something other than the timestamp moved."""
        status = {**status, "map_version": self._map_version}
        changed = _without_timestamp(status) != _without_timestamp(self._status)
        self._status = status
        if changed:
            self._publish(("status", status))
        return changed

    def set_map(self, png: bytes | None) -> bool:
        if not png:
            return False
        digest = hashlib.sha256(png).hexdigest()
        if digest == self._map_digest:
            return False
        self._map, self._map_digest = png, digest
        self._map_version += 1
        self._status = {**self._status, "map_version": self._map_version}
        self._publish(("map", {"version": self._map_version}))
        return True

    def subscribe(self) -> asyncio.Queue[Event | None]:
        queue: asyncio.Queue[Event | None] = asyncio.Queue(maxsize=_SUBSCRIBER_BACKLOG)
        self._subscribers.add(queue)
        return queue

    def unsubscribe(self, queue: asyncio.Queue[Event | None]) -> None:
        self._subscribers.discard(queue)

    def close(self) -> None:
        """Tell every subscriber the stream is over."""
        for queue in self._subscribers:
            self._offer(queue, None)

    def _publish(self, event: Event) -> None:
        for queue in self._subscribers:
            self._offer(queue, event)

    @staticmethod
    def _offer(queue: asyncio.Queue[Event | None], event: Event | None) -> None:
        # A stalled browser tab must not grow memory without bound: drop its oldest
        # event. Each event carries full state, so the next one catches it up.
        if queue.full():
            with contextlib.suppress(asyncio.QueueEmpty):
                queue.get_nowait()
        queue.put_nowait(event)


def _without_timestamp(status: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in status.items() if k != "updated_at"}


def _default_factory(credentials: config.Credentials) -> Vacuum:
    return RoborockVacuum(credentials, device_id=os.environ.get(config.DEVICE_ENV) or None)


class VacuumService:
    def __init__(
        self,
        store: StateStore,
        vacuum_factory: VacuumFactory | None = None,
        *,
        poll_parked: float = 60.0,
        poll_active: float = 10.0,
        map_parked: float = 600.0,
        backoff_initial: float = 5.0,
        backoff_max: float = 300.0,
    ) -> None:
        self._store = store
        self._factory = vacuum_factory or _default_factory
        self._poll_parked = poll_parked
        self._poll_active = poll_active
        self._map_parked = map_parked
        self._backoff_initial = backoff_initial
        self._backoff_max = backoff_max
        self._vacuum: Vacuum | None = None
        self._task: asyncio.Task[None] | None = None
        self._wake = asyncio.Event()
        self._command_lock = asyncio.Lock()
        self._unavailable = ServiceUnavailable("not_connected", "The daemon has not connected to the vacuum yet.")
        self._map_fetched_at = 0.0

    async def start(self) -> None:
        if self._task is None:
            self._task = asyncio.create_task(self._run(), name="vacuum-service")

    async def stop(self) -> None:
        task, self._task = self._task, None
        if task is not None:
            task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await task

    async def reload(self) -> None:
        """Drop the connection and start over, re-reading credentials. Called after a login."""
        await self.stop()
        await self.start()

    async def command(self, action: str, params: dict[str, Any] | None = None) -> Any:
        async with self._command_lock:
            if self._vacuum is None:
                raise self._unavailable
            result = await self._vacuum.command(action, params)
        self._wake.set()  # refresh now rather than at the next poll, so callers see the effect
        return result

    async def _run(self) -> None:
        backoff = self._backoff_initial
        while True:
            try:
                credentials = auth.require_credentials()
            except auth.NotAuthenticatedError as err:
                self._offline("not_authenticated", str(err), authenticated=False)
                return  # nothing to retry until a login lands; `reload` restarts us
            vacuum = self._factory(credentials)
            try:
                await vacuum.connect()
                vacuum.on_update(self._on_push)
                self._vacuum = vacuum
                backoff = self._backoff_initial
                await self._poll(vacuum)
                return  # _poll only returns when the cloud rejected our login
            except DeviceError as err:
                _LOGGER.warning("Vacuum connection failed: %s", err)
                self._offline("not_connected", str(err), authenticated=True)
            except Exception as err:  # noqa: BLE001 - one bad poll must not end the daemon's only loop
                _LOGGER.exception("Unexpected failure talking to the vacuum")
                self._offline("not_connected", f"Unexpected error: {err}", authenticated=True)
            finally:
                self._vacuum = None
                with contextlib.suppress(Exception):
                    await vacuum.close()
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, self._backoff_max)

    async def _poll(self, vacuum: Vacuum) -> None:
        while True:
            self._wake.clear()
            if vacuum.credentials_rejected:
                self._vacuum = None
                self._offline(
                    "not_authenticated",
                    "Roborock rejected the stored login. Run `rrctl setup` to log in again.",
                    authenticated=False,
                )
                return
            active = False
            try:
                snapshot = await vacuum.status()
                self._store.set_status(self._online(snapshot))
                active = _is_active(snapshot)
                await self._refresh_map(vacuum, active)
            except DeviceError as err:
                # python-roborock reconnects underneath us, so keep polling rather than tearing down.
                _LOGGER.info("Poll failed: %s", err)
                self._store.set_status(
                    {**self._store.status, "connected": False, "error": str(err), "updated_at": time.time()}
                )
            with contextlib.suppress(asyncio.TimeoutError):
                await asyncio.wait_for(self._wake.wait(), self._poll_active if active else self._poll_parked)

    async def _refresh_map(self, vacuum: Vacuum, active: bool) -> None:
        now = time.monotonic()
        if self._store.map_png is not None and not active and now - self._map_fetched_at < self._map_parked:
            return
        self._map_fetched_at = now
        self._store.set_map(await vacuum.map_png())

    def _on_push(self, snapshot: dict[str, Any]) -> None:
        self._store.set_status(self._online(snapshot))

    def _online(self, snapshot: dict[str, Any]) -> dict[str, Any]:
        return {"authenticated": True, "connected": True, "error": None, "updated_at": time.time(), **snapshot}

    def _offline(self, code: str, message: str, *, authenticated: bool) -> None:
        self._unavailable = ServiceUnavailable(code, message)
        status: dict[str, Any] = {
            "authenticated": authenticated,
            "connected": False,
            "error": message,
            "updated_at": time.time(),
        }
        if not authenticated:
            status["hint"] = auth.SETUP_HINT
        self._store.set_status(status)


def _is_active(snapshot: dict[str, Any]) -> bool:
    state = snapshot.get("state_code")
    return bool(snapshot.get("in_returning")) or (state is not None and state not in _PARKED_STATES)
