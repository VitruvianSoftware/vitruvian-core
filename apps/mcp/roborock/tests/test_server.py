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
import json

import pytest

pytest.importorskip("aiohttp")
from aiohttp.test_utils import TestClient, TestServer  # noqa: E402

from vitruvian_roborock.daemon.client import DaemonClient, DaemonRequestError, DaemonUnavailable  # noqa: E402
from vitruvian_roborock.daemon.server import create_app  # noqa: E402
from vitruvian_roborock.daemon.state import StateStore, VacuumService  # noqa: E402

from conftest import PNG, until  # noqa: E402

TOKEN = "test-token-0123456789"
AUTH = {"Authorization": f"Bearer {TOKEN}"}


def run(scenario, vacuum, *, wait_connected=True):
    """Start a real daemon app on an ephemeral loopback port and hand the scenario a client."""

    async def main():
        store = StateStore()
        service = VacuumService(store, lambda credentials: vacuum, backoff_initial=0.01)
        stop = asyncio.Event()
        async with TestClient(TestServer(create_app(store, service, TOKEN, stop))) as client:
            await service.start()
            try:
                if wait_connected:
                    await until(lambda: store.map_png is not None)
                await scenario(client, store, stop)
            finally:
                await service.stop()

    asyncio.run(main())


def test_requests_without_the_token_are_refused(logged_in, vacuum):
    async def scenario(client, store, stop):
        for path in ("/status", "/map.png", "/events"):
            assert (await client.get(path)).status == 401
        assert (await client.get("/status", headers={"Authorization": "Bearer wrong"})).status == 401
        assert (await client.get("/status", headers={"Authorization": f"Basic {TOKEN}"})).status == 401
        assert (await client.post("/command", json={"command": "pause"})).status == 401
        assert vacuum.commands == []

    run(scenario, vacuum)


def test_token_in_the_query_string_is_not_accepted(logged_in, vacuum):
    async def scenario(client, store, stop):
        assert (await client.get(f"/status?token={TOKEN}")).status == 401

    run(scenario, vacuum)


def test_cross_origin_requests_are_refused_even_with_the_token(logged_in, vacuum):
    async def scenario(client, store, stop):
        for origin in ("https://evil.example", "http://127.0.0.1:1", "null"):
            response = await client.post("/command", json={"command": "pause"}, headers={**AUTH, "Origin": origin})
            assert response.status == 403, origin
            assert (await response.json())["error"] == "forbidden_origin"
        assert vacuum.commands == []
        own = f"http://127.0.0.1:{client.port}"
        assert (await client.get("/status", headers={**AUTH, "Origin": own})).status == 200

    run(scenario, vacuum)


def test_a_foreign_host_header_is_refused(logged_in, vacuum):
    """DNS rebinding: a page on evil.example whose name resolves to 127.0.0.1."""

    async def scenario(client, store, stop):
        response = await client.get("/status", headers={**AUTH, "Host": f"evil.example:{client.port}"})
        assert response.status == 403
        assert (await response.json())["error"] == "forbidden_host"
        assert (await client.get("/status", headers={**AUTH, "Host": f"localhost:{client.port}"})).status == 200

    run(scenario, vacuum)


def test_no_response_grants_cross_origin_access(logged_in, vacuum):
    async def scenario(client, store, stop):
        response = await client.get("/status", headers=AUTH)
        assert not [name for name in response.headers if name.lower().startswith("access-control-")]
        assert response.headers["Cache-Control"] == "no-store"

    run(scenario, vacuum)


def test_dashboard_and_health_are_public_but_carry_no_secrets(logged_in, vacuum):
    async def scenario(client, store, stop):
        page = await client.get("/")
        assert page.status == 200 and page.content_type == "text/html"
        assert "frame-ancestors 'none'" in page.headers["Content-Security-Policy"]
        body = await page.text()
        assert "<canvas" in body and TOKEN not in body
        health = await (await client.get("/healthz")).json()
        assert health["service"] == "vitruvian-roborock" and health["ok"] is True
        assert TOKEN not in json.dumps(health)

    run(scenario, vacuum)


def test_status_and_map(logged_in, vacuum):
    async def scenario(client, store, stop):
        status = await (await client.get("/status", headers=AUTH)).json()
        assert (status["connected"], status["battery"], status["map_version"]) == (True, 100, 1)
        picture = await client.get("/map.png", headers=AUTH)
        assert picture.content_type == "image/png" and await picture.read() == PNG
        cached = await client.get("/map.png", headers={**AUTH, "If-None-Match": picture.headers["ETag"]})
        assert cached.status == 304

    run(scenario, vacuum)


def test_map_is_404_until_one_arrives(logged_in, vacuum):
    vacuum.png = None

    async def scenario(client, store, stop):
        await until(lambda: store.status.get("connected"))
        response = await client.get("/map.png", headers=AUTH)
        assert response.status == 404 and (await response.json())["error"] == "no_map"

    run(scenario, vacuum, wait_connected=False)


def test_command_round_trip_and_its_refusals(logged_in, vacuum):
    async def scenario(client, store, stop):
        ok = await client.post("/command", json={"command": "clean_rooms", "params": {"rooms": ["Kitchen"]}}, headers=AUTH)
        assert ok.status == 200
        assert await ok.json() == {"ok": True, "command": "clean_rooms", "result": ["ok"]}
        assert vacuum.commands == [("clean_rooms", {"rooms": ["Kitchen"]})]

        cases = [
            ({"json": {"command": "bogus"}}, 400, "unknown_command"),
            ({"json": {"command": "wash_start"}}, 502, "device_error"),
            ({"json": {}}, 400, "bad_request"),
            ({"json": {"command": "pause", "params": [1]}}, 400, "bad_request"),
            ({"json": ["pause"]}, 400, "bad_request"),
            ({"data": "{", "headers": {"Content-Type": "application/json"}}, 400, "bad_request"),
            # A cross-site <form> can only send these content types; refusing them blocks form CSRF.
            ({"data": {"command": "pause"}}, 415, "unsupported_media_type"),
            ({"data": '{"command": "pause"}', "headers": {"Content-Type": "text/plain"}}, 415, "unsupported_media_type"),
        ]
        for kwargs, status, code in cases:
            headers = {**AUTH, **kwargs.pop("headers", {})}
            response = await client.post("/command", headers=headers, **kwargs)
            assert (response.status, (await response.json())["error"]) == (status, code), kwargs
        assert len(vacuum.commands) == 1

    run(scenario, vacuum)


def test_commands_without_a_login_answer_409_with_the_reason(vacuum):
    async def scenario(client, store, stop):
        await until(lambda: "hint" in store.status)
        status = await (await client.get("/status", headers=AUTH)).json()
        assert status["authenticated"] is False and "rrctl setup" in status["hint"]
        response = await client.post("/command", json={"command": "pause"}, headers=AUTH)
        assert response.status == 409
        assert (await response.json())["error"] == "not_authenticated"

    run(scenario, vacuum, wait_connected=False)


def test_commands_while_disconnected_answer_503(logged_in, vacuum):
    vacuum.fail_connect = 10_000

    async def scenario(client, store, stop):
        await until(lambda: store.status.get("error") == "cloud unreachable")
        response = await client.post("/command", json={"command": "pause"}, headers=AUTH)
        assert (response.status, (await response.json())["error"]) == (503, "not_connected")

    run(scenario, vacuum, wait_connected=False)


async def read_event(response):
    event, data = None, None
    while True:
        line = (await asyncio.wait_for(response.content.readline(), 2)).decode().rstrip("\n")
        if line.startswith("event:"):
            event = line[6:].strip()
        elif line.startswith("data:"):
            data = json.loads(line[5:])
        elif not line and event:
            return event, data


def test_event_stream_sends_current_state_then_changes(logged_in, vacuum):
    async def scenario(client, store, stop):
        async with client.get("/events", headers=AUTH) as response:
            assert response.status == 200 and response.content_type == "text/event-stream"
            event, data = await read_event(response)
            assert event == "status" and data["state"] == "charging"

            vacuum.listener({**vacuum.snapshot, "state": "cleaning", "state_code": 5})
            event, data = await read_event(response)
            assert event == "status" and data["state"] == "cleaning"

            store.set_map(PNG + b"new")
            assert await read_event(response) == ("map", {"version": 2})

    run(scenario, vacuum)


def test_shutdown_sets_the_stop_signal(logged_in, vacuum):
    async def scenario(client, store, stop):
        assert (await client.post("/shutdown", json={})).status == 401
        assert not stop.is_set()
        assert (await client.post("/shutdown", json={}, headers=AUTH)).status == 200
        assert stop.is_set()

    run(scenario, vacuum)


def test_python_client_end_to_end(logged_in, vacuum, monkeypatch):
    """The stdlib client the CLI and MCP server use, against the real HTTP app."""
    # A proxy from the environment must not be used for loopback; an unreachable one proves it.
    monkeypatch.setenv("HTTP_PROXY", "http://127.0.0.1:9")
    monkeypatch.setenv("http_proxy", "http://127.0.0.1:9")
    monkeypatch.delenv("NO_PROXY", raising=False)
    monkeypatch.delenv("no_proxy", raising=False)

    async def scenario(client, store, stop):
        api = DaemonClient(port=client.port, token=TOKEN, timeout=5)

        def calls():
            assert api.health()["service"] == "vitruvian-roborock"
            assert api.status()["battery"] == 100
            assert api.map_png() == PNG
            assert api.command("pause") == {"ok": True, "command": "pause", "result": ["ok"]}
            with pytest.raises(DaemonRequestError) as refused:
                api.command("bogus")
            assert (refused.value.status, refused.value.code) == (400, "unknown_command")
            with pytest.raises(DaemonRequestError) as wrong:
                DaemonClient(port=client.port, token="wrong", timeout=5).status()
            assert wrong.value.code == "unauthorized"
            assert api.reload() == {"ok": True}

        await asyncio.to_thread(calls)
        await until(lambda: store.status.get("connected"))

    run(scenario, vacuum)


def test_python_client_reports_a_missing_daemon_and_a_missing_token(monkeypatch):
    import socket

    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        free_port = probe.getsockname()[1]
    api = DaemonClient(port=free_port, token=TOKEN, timeout=1)
    assert api.health() is None
    with pytest.raises(DaemonUnavailable, match="not reachable"):
        api.status()
    with pytest.raises(DaemonUnavailable, match="No daemon token"):
        DaemonClient(port=free_port).status()


def test_a_foreign_program_on_the_port_is_named_instead_of_spawning_into_it(monkeypatch):
    """Something else answering 200 on our port must not be mistaken for the daemon."""
    import http.server
    import threading

    from vitruvian_roborock.daemon import client as daemon_client

    class Anything(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{"ok": true}')

        def log_message(self, *args):
            pass

    server = http.server.HTTPServer(("127.0.0.1", 0), Anything)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    spawned = []
    monkeypatch.setattr(daemon_client, "spawn_daemon", lambda port=None: spawned.append(port))
    try:
        port = server.server_address[1]
        assert DaemonClient(port=port, token=TOKEN).health() is None
        with pytest.raises(DaemonUnavailable, match=f"Port {port} is in use by another program"):
            daemon_client.ensure_running(port)
        assert spawned == []
    finally:
        server.shutdown()
        server.server_close()
