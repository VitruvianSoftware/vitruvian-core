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

"""The vacuum itself: one connection, a status snapshot, the map and commands.

`Vacuum` is the seam the daemon is written against. `RoborockVacuum` is the only
implementation that talks to hardware; tests substitute their own. python-roborock
is imported inside the methods that need it so the rest of the package (and
`rrctl setup` before any login exists) loads without it.
"""

from __future__ import annotations

import logging
from collections.abc import Callable
from pathlib import Path
from typing import Any, Protocol

from vitruvian_roborock.core import config

_LOGGER = logging.getLogger(__name__)

# Action name -> raw Roborock command. `resume` and `clean_rooms` are not here:
# they depend on the vacuum's state and are resolved in `RoborockVacuum.command`.
SIMPLE_ACTIONS: dict[str, str] = {
    "start": "app_start",
    "pause": "app_pause",
    "stop": "app_stop",
    "dock": "app_charge",
    "find": "find_me",
    "wash_start": "app_start_wash",
    "wash_stop": "app_stop_wash",
}
ACTIONS: tuple[str, ...] = (*SIMPLE_ACTIONS, "resume", "clean_rooms")

# Status.in_cleaning: which kind of clean was interrupted, and so how to resume it.
_RESUME_BY_IN_CLEANING = {2: "resume_zoned_clean", 3: "resume_segment_clean"}


class DeviceError(Exception):
    """The vacuum rejected a request or could not be reached."""


class UnknownActionError(DeviceError):
    """The caller asked for something that is not a supported action."""


class Vacuum(Protocol):
    async def connect(self) -> None: ...

    async def close(self) -> None: ...

    async def status(self) -> dict[str, Any]: ...

    async def map_png(self) -> bytes | None: ...

    async def command(self, action: str, params: dict[str, Any] | None = None) -> Any: ...

    def on_update(self, callback: Callable[[dict[str, Any]], None]) -> None: ...

    @property
    def credentials_rejected(self) -> bool: ...


def _int(value: Any) -> int | None:
    """Roborock enums and plain ints both come back as codes; give callers the number."""
    if value is None:
        return None
    return int(getattr(value, "value", value))


def _safe(read: Callable[[], Any]) -> Any:
    # The *_name helpers derive from device features, which may not be loaded yet.
    try:
        return read()
    except Exception:  # noqa: BLE001 - a missing label must not cost us the whole snapshot
        return None


class RoborockVacuum:
    """A V1-protocol Roborock vacuum reached through python-roborock's device manager."""

    def __init__(
        self,
        credentials: config.Credentials,
        *,
        device_id: str | None = None,
        cache_file: Path | None = None,
    ) -> None:
        self._credentials = credentials
        self._device_id = device_id
        self._cache_file = cache_file or config.cache_path()
        self._manager: Any = None
        self._cache: Any = None
        self._device: Any = None
        self._props: Any = None
        self._unsubscribe: list[Callable[[], None]] = []
        self._listeners: list[Callable[[dict[str, Any]], None]] = []
        self._rooms: list[dict[str, Any]] = []
        self._credentials_rejected = False

    @property
    def credentials_rejected(self) -> bool:
        return self._credentials_rejected

    def on_update(self, callback: Callable[[dict[str, Any]], None]) -> None:
        self._listeners.append(callback)

    async def connect(self) -> None:
        from roborock.data import UserData
        from roborock.devices.device_manager import UserParams, create_device_manager
        from roborock.devices.file_cache import FileCache
        from roborock.exceptions import RoborockException

        config.ensure_private_dir(self._cache_file.parent)
        self._cache = FileCache(self._cache_file)
        params = UserParams(
            username=self._credentials.email,
            user_data=UserData.from_dict(self._credentials.user_data),
            base_url=self._credentials.base_url,
        )
        try:
            self._manager = await create_device_manager(
                params,
                cache=self._cache,
                mqtt_session_unauthorized_hook=self._on_unauthorized,
            )
            devices = await self._manager.get_devices()
        except RoborockException as err:
            raise DeviceError(f"Could not reach the Roborock cloud: {err}") from err
        self._device = self._select(devices)
        self._props = self._device.v1_properties
        self._unsubscribe.append(self._props.status.add_update_listener(self._on_status_update))

    def _select(self, devices: list[Any]) -> Any:
        vacuums = [d for d in devices if getattr(d, "v1_properties", None) is not None]
        if self._device_id:
            for device in devices:
                if self._device_id in (device.duid, device.name):
                    if device not in vacuums:
                        raise DeviceError(f"{device.name} uses a protocol this version does not support yet.")
                    return device
            raise DeviceError(f"No device named or identified as {self._device_id!r} on this account.")
        if not vacuums:
            if devices:
                raise DeviceError("The devices on this account use a protocol this version does not support yet.")
            raise DeviceError("This Roborock account has no devices.")
        if len(vacuums) > 1:
            names = ", ".join(d.name for d in vacuums)
            _LOGGER.warning("Several vacuums found (%s); using %s. Set %s to choose.", names, vacuums[0].name, config.DEVICE_ENV)
        return vacuums[0]

    def _on_unauthorized(self) -> None:
        self._credentials_rejected = True

    def _on_status_update(self) -> None:
        snapshot = self._snapshot()
        for listener in self._listeners:
            listener(snapshot)

    async def close(self) -> None:
        for unsubscribe in self._unsubscribe:
            unsubscribe()
        self._unsubscribe.clear()
        if self._manager is not None:
            await self._manager.close()
            self._manager = None
        if self._cache is not None:
            await self._cache.flush()
            self._cache = None
        self._device = None
        self._props = None

    def _require(self) -> Any:
        if self._props is None:
            raise DeviceError("Not connected to the vacuum yet.")
        return self._props

    async def status(self) -> dict[str, Any]:
        from roborock.exceptions import RoborockException

        props = self._require()
        try:
            await props.status.refresh()
        except RoborockException as err:
            raise DeviceError(f"The vacuum did not answer: {err}") from err
        if not self._rooms:
            await self._load_rooms()
        return self._snapshot()

    async def _load_rooms(self) -> None:
        from roborock.exceptions import RoborockException

        try:
            await self._props.rooms.refresh()
        except RoborockException as err:
            _LOGGER.debug("Could not load rooms: %s", err)
            return
        self._rooms = [
            {"id": room.segment_id, "name": _safe(lambda room=room: room.name) or room.raw_name or str(room.segment_id)}
            for room in (self._props.rooms.rooms or [])
        ]

    def _snapshot(self) -> dict[str, Any]:
        status = self._props.status
        error_code = _int(status.error_code)
        dock_error = _int(status.dock_error_status)
        return {
            "device": {
                "id": self._device.duid,
                "name": self._device.name,
                "model": _safe(lambda: self._device.product.model),
                "local": bool(_safe(lambda: self._device.is_local_connected)),
            },
            "state": _safe(lambda: status.state_name),
            "state_code": _int(status.state),
            "battery": status.battery,
            "error": _safe(lambda: status.error_code_name) if error_code else None,
            "error_code": error_code or None,
            "dock_error_code": dock_error or None,
            "clean_time_s": status.clean_time,
            "clean_area_m2": _safe(lambda: status.square_meter_clean_area),
            "clean_percent": status.clean_percent,
            "in_cleaning": bool(_int(status.in_cleaning)),
            "in_returning": bool(status.in_returning),
            "fan_speed": _safe(lambda: status.fan_speed_name),
            "water_mode": _safe(lambda: status.water_mode_name),
            "mop_route": _safe(lambda: status.mop_route_name),
            "rooms": self._rooms,
        }

    async def map_png(self) -> bytes | None:
        from roborock.exceptions import RoborockException

        props = self._require()
        try:
            await props.map_content.refresh()
        except RoborockException as err:
            raise DeviceError(f"Could not fetch the map: {err}") from err
        return props.map_content.image_content

    async def command(self, action: str, params: dict[str, Any] | None = None) -> Any:
        from roborock.exceptions import RoborockException

        props = self._require()
        params = params or {}
        raw, raw_params = self._resolve(action, params)
        try:
            return await props.command.send(raw, raw_params)
        except RoborockException as err:
            raise DeviceError(f"The vacuum refused '{action}': {err}") from err

    def _resolve(self, action: str, params: dict[str, Any]) -> tuple[str, Any]:
        if action in SIMPLE_ACTIONS:
            return SIMPLE_ACTIONS[action], None
        if action == "resume":
            in_cleaning = _int(self._props.status.in_cleaning)
            return _RESUME_BY_IN_CLEANING.get(in_cleaning or 0, "app_start"), None
        if action == "clean_rooms":
            segments = resolve_rooms(params.get("rooms") or [], self._rooms)
            repeat = int(params.get("repeat") or 1)
            if not 1 <= repeat <= 3:
                raise DeviceError("repeat must be 1, 2 or 3.")
            return "app_segment_clean", [{"segments": segments, "repeat": repeat}]
        raise UnknownActionError(f"Unknown action {action!r}. Supported: {', '.join(ACTIONS)}.")


def resolve_rooms(wanted: list[Any], known: list[dict[str, Any]]) -> list[int]:
    """Map room names or segment ids from a caller onto the vacuum's segment ids."""
    if not wanted:
        raise DeviceError("clean_rooms needs at least one room.")
    by_name = {str(room["name"]).casefold(): room["id"] for room in known}
    ids = {room["id"] for room in known}
    segments: list[int] = []
    for item in wanted:
        text = str(item).strip()
        if text.casefold() in by_name:
            segments.append(by_name[text.casefold()])
        elif text.isdigit() and int(text) in ids:
            segments.append(int(text))
        else:
            available = ", ".join(str(room["name"]) for room in known) or "none reported by the vacuum"
            raise DeviceError(f"Unknown room {text!r}. Available: {available}.")
    return list(dict.fromkeys(segments))
