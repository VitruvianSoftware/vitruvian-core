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

"""The local HTTP face of the daemon.

Bound to loopback only. A browser on this machine can still reach loopback from
any web page, so three checks stand between a request and the vacuum: the Host
header (DNS rebinding), the Origin header (cross-site requests), and a bearer
token that only local processes able to read our config directory have.
"""

from __future__ import annotations

import asyncio
import contextlib
import hmac
import json
import logging
import os
import signal
from typing import Any

from aiohttp import web

from vitruvian_roborock import __version__
from vitruvian_roborock.core import config
from vitruvian_roborock.core.device import DeviceError, UnknownActionError
from vitruvian_roborock.daemon.state import ServiceUnavailable, StateStore, VacuumService
from vitruvian_roborock.dashboard import dashboard_html

_LOGGER = logging.getLogger(__name__)

SERVICE_NAME = "vitruvian-roborock"
_PUBLIC_PATHS = frozenset({"/", "/healthz"})
_HEARTBEAT_SECONDS = 15.0

_DASHBOARD_CSP = (
    "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; "
    "img-src 'self' blob: data:; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
)

STORE = web.AppKey("store", StateStore)
SERVICE = web.AppKey("service", VacuumService)
STOP = web.AppKey("stop", asyncio.Event)


def _problem(status: int, code: str, message: str, **extra: Any) -> web.Response:
    return web.json_response({"ok": False, "error": code, "message": message, **extra}, status=status)


def _guard(token: str) -> Any:
    expected = token.encode()

    @web.middleware
    async def guard(request: web.Request, handler: Any) -> web.StreamResponse:
        sockname = request.transport.get_extra_info("sockname") if request.transport else None
        port = sockname[1] if sockname else config.daemon_port()
        hosts = {f"127.0.0.1:{port}", f"localhost:{port}"}
        if request.headers.get("Host", "") not in hosts:
            return _problem(403, "forbidden_host", "This daemon only answers on its loopback address.")
        origin = request.headers.get("Origin")
        if origin is not None and origin not in {f"http://{host}" for host in hosts}:
            return _problem(403, "forbidden_origin", "Cross-origin requests are not allowed.")
        if request.path not in _PUBLIC_PATHS:
            scheme, _, presented = request.headers.get("Authorization", "").partition(" ")
            if scheme.lower() != "bearer" or not hmac.compare_digest(presented.strip().encode(), expected):
                return _problem(401, "unauthorized", "Missing or wrong daemon token.")
        if request.method == "POST" and request.content_type != "application/json":
            return _problem(415, "unsupported_media_type", "POST bodies must be application/json.")
        response = await handler(request)
        response.headers.setdefault("Cache-Control", "no-store")
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        return response

    return guard


async def _index(_: web.Request) -> web.Response:
    return web.Response(
        text=dashboard_html(),
        content_type="text/html",
        headers={"Content-Security-Policy": _DASHBOARD_CSP, "X-Frame-Options": "DENY"},
    )


async def _healthz(_: web.Request) -> web.Response:
    return web.json_response({"ok": True, "service": SERVICE_NAME, "version": __version__, "pid": os.getpid()})


async def _status(request: web.Request) -> web.Response:
    return web.json_response(request.app[STORE].status)


async def _map(request: web.Request) -> web.Response:
    store = request.app[STORE]
    if store.map_png is None:
        return _problem(404, "no_map", "No map has been received from the vacuum yet.")
    etag = f'"{store.map_version}"'
    if request.headers.get("If-None-Match") == etag:
        return web.Response(status=304, headers={"ETag": etag})
    return web.Response(body=store.map_png, content_type="image/png", headers={"ETag": etag})


async def _events(request: web.Request) -> web.StreamResponse:
    store = request.app[STORE]
    response = web.StreamResponse(headers={"Content-Type": "text/event-stream", "X-Accel-Buffering": "no"})
    await response.prepare(request)
    queue = store.subscribe()
    try:
        await response.write(_sse("status", store.status))
        while True:
            try:
                event = await asyncio.wait_for(queue.get(), _HEARTBEAT_SECONDS)
            except asyncio.TimeoutError:
                await response.write(b": keep-alive\n\n")
                continue
            if event is None:
                break
            await response.write(_sse(*event))
    except (ConnectionResetError, asyncio.CancelledError):
        pass
    finally:
        store.unsubscribe(queue)
    return response


def _sse(event: str, data: dict[str, Any]) -> bytes:
    return f"event: {event}\ndata: {json.dumps(data)}\n\n".encode()


async def _command(request: web.Request) -> web.Response:
    try:
        body = await request.json()
    except ValueError:
        return _problem(400, "bad_request", "The body is not valid JSON.")
    action = body.get("command") if isinstance(body, dict) else None
    params = body.get("params") if isinstance(body, dict) else None
    if not isinstance(action, str) or not action:
        return _problem(400, "bad_request", "Give the action as a string in 'command'.")
    if params is not None and not isinstance(params, dict):
        return _problem(400, "bad_request", "'params' must be an object.")
    try:
        result = await request.app[SERVICE].command(action, params)
    except ServiceUnavailable as err:
        return _problem(409 if err.code == "not_authenticated" else 503, err.code, str(err))
    except UnknownActionError as err:
        return _problem(400, "unknown_command", str(err))
    except DeviceError as err:
        return _problem(502, "device_error", str(err))
    return web.json_response({"ok": True, "command": action, "result": result})


async def _reload(request: web.Request) -> web.Response:
    await request.app[SERVICE].reload()
    return web.json_response({"ok": True})


async def _shutdown(request: web.Request) -> web.Response:
    request.app[STOP].set()
    return web.json_response({"ok": True})


def create_app(
    store: StateStore, service: VacuumService, token: str, stop: asyncio.Event | None = None
) -> web.Application:
    app = web.Application(middlewares=[_guard(token)], client_max_size=64 * 1024)
    app[STORE] = store
    app[SERVICE] = service
    app[STOP] = stop or asyncio.Event()
    app.add_routes(
        [
            web.get("/", _index),
            web.get("/healthz", _healthz),
            web.get("/status", _status),
            web.get("/map.png", _map),
            web.get("/events", _events),
            web.post("/command", _command),
            web.post("/reload", _reload),
            web.post("/shutdown", _shutdown),
        ]
    )

    async def close_streams(_: web.Application) -> None:
        store.close()

    app.on_shutdown.append(close_streams)
    return app


class PortInUse(Exception):
    pass


async def serve(port: int | None = None) -> None:
    """Run the daemon until SIGINT, SIGTERM or POST /shutdown."""
    port = port or config.daemon_port()
    token = config.load_or_create_token()
    store = StateStore()
    service = VacuumService(store)
    stop = asyncio.Event()
    runner = web.AppRunner(create_app(store, service, token, stop), access_log=None)
    await runner.setup()
    try:
        try:
            await web.TCPSite(runner, config.DAEMON_HOST, port).start()
        except OSError as err:
            raise PortInUse(f"Cannot listen on {config.DAEMON_HOST}:{port}: {err.strerror or err}") from err
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGINT, signal.SIGTERM):
            with contextlib.suppress(NotImplementedError):  # Windows event loops
                loop.add_signal_handler(sig, stop.set)
        await service.start()
        _LOGGER.info("Listening on http://%s:%s", config.DAEMON_HOST, port)
        await stop.wait()
    finally:
        await service.stop()
        await runner.cleanup()
