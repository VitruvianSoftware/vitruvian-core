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

pytest.importorskip("mcp")

from vitruvian_roborock.core import auth, config  # noqa: E402
from vitruvian_roborock.daemon.client import DaemonRequestError, DaemonUnavailable  # noqa: E402
from vitruvian_roborock.mcp.server import build_server  # noqa: E402
from vitruvian_roborock.mcp.tools import Bridge  # noqa: E402

from conftest import PNG, STATUS, USER_DATA  # noqa: E402


class FakeDaemon:
    def __init__(self) -> None:
        self.commands: list = []
        self.png: bytes | None = PNG
        self.doc: dict = {"authenticated": True, "connected": True, **STATUS}
        self.refuse: Exception | None = None

    def status(self):
        return self.doc

    def map_png(self):
        if self.refuse:
            raise self.refuse
        return self.png

    def command(self, action, params=None):
        if self.refuse:
            raise self.refuse
        self.commands.append((action, params))
        return {"ok": True, "command": action}


class FakeApi:
    async def request_code_v4(self):
        pass

    async def code_login_v4(self, code):
        if code != "123456":
            raise RuntimeError("bad code")
        return dict(USER_DATA)


@pytest.fixture
def daemon():
    return FakeDaemon()


@pytest.fixture
def server(daemon):
    bridge = Bridge(client_factory=lambda: daemon, login_flow=auth.LoginFlow(client_factory=lambda email: FakeApi()))

    async def not_running():
        return False

    bridge.reload_if_running = not_running
    return build_server(bridge)


def call(server, name, **arguments):
    return asyncio.run(server.call_tool(name, arguments))


def test_the_agreed_tools_and_resources_are_exposed(server):
    async def listing():
        return await server.list_tools(), await server.list_resources()

    tools, resources = asyncio.run(listing())
    assert {tool.name for tool in tools} == {
        "get_status",
        "start_clean",
        "control",
        "return_to_dock",
        "wash_mop",
        "get_map",
        "setup_login",
    }
    assert {str(resource.uri): resource.mime_type for resource in resources} == {
        "roborock://status": "application/json",
        "roborock://map.png": "image/png",
        "ui://dashboard": "text/html;profile=mcp-app",
    }
    by_name = {tool.name: tool for tool in tools}
    assert by_name["get_status"].meta == {"ui": {"resourceUri": "ui://dashboard"}}
    assert by_name["get_status"].annotations.read_only_hint is True
    assert by_name["control"].input_schema["properties"]["action"]["enum"] == ["pause", "resume", "stop", "find"]
    assert all(tool.description for tool in tools)


def test_get_status_returns_the_daemon_document(server):
    assert call(server, "get_status").structured_content["state"] == "charging"


def test_unauthenticated_status_is_an_answer_not_an_error(server, daemon):
    daemon.doc = {"authenticated": False, "connected": False, "hint": auth.SETUP_HINT}
    result = call(server, "get_status")
    assert not result.is_error
    assert result.structured_content == daemon.doc


def test_commands_while_logged_out_explain_what_to_do(server, daemon):
    daemon.refuse = DaemonRequestError(409, {"ok": False, "error": "not_authenticated", "message": "Not logged in."})
    for name, arguments in [
        ("start_clean", {}),
        ("control", {"action": "pause"}),
        ("return_to_dock", {}),
        ("wash_mop", {}),
    ]:
        result = call(server, name, **arguments)
        assert not result.is_error, name
        assert result.structured_content["error"] == "not_authenticated"
        assert "setup_login" in result.structured_content["hint"]
    assert "Not logged in." in call(server, "get_map").content[0].text


def test_a_daemon_that_will_not_start_is_reported_plainly(daemon):
    def cannot_start():
        raise DaemonUnavailable("The daemon did not start on port 8765.")

    server = build_server(Bridge(client_factory=cannot_start))
    assert call(server, "get_status").structured_content == {
        "ok": False,
        "error": "daemon_unavailable",
        "message": "The daemon did not start on port 8765.",
    }
    assert "did not start" in call(server, "get_map").content[0].text


def test_action_tools_send_the_right_daemon_commands(server, daemon):
    call(server, "start_clean")
    call(server, "start_clean", rooms=["Kitchen", "Living Room"], repeat=2)
    call(server, "control", action="pause")
    call(server, "control", action="resume")
    call(server, "return_to_dock")
    call(server, "wash_mop")
    call(server, "wash_mop", action="stop")
    assert daemon.commands == [
        ("start", None),
        ("clean_rooms", {"rooms": ["Kitchen", "Living Room"], "repeat": 2}),
        ("pause", None),
        ("resume", None),
        ("dock", None),
        ("wash_start", None),
        ("wash_stop", None),
    ]


def test_control_rejects_actions_outside_its_list(server, daemon):
    from mcp.server.mcpserver.exceptions import ToolError

    with pytest.raises(ToolError, match="Input should be 'pause', 'resume', 'stop' or 'find'"):
        call(server, "control", action="self_destruct")
    assert daemon.commands == []


def test_get_map_returns_a_png_image_or_says_why_not(server, daemon):
    import base64

    picture = call(server, "get_map").content[0]
    assert (picture.type, picture.mime_type) == ("image", "image/png")
    assert base64.b64decode(picture.data) == PNG
    daemon.png = None
    assert "not sent a map yet" in call(server, "get_map").content[0].text


def test_setup_login_is_two_steps_and_stores_the_login(server):
    first = call(server, "setup_login", email="me@example.com").structured_content
    assert first["ok"] is True and first["authenticated"] is False and "code" in first["next"]
    assert config.load_credentials() is None

    wrong = call(server, "setup_login", email="me@example.com", code="999999").structured_content
    assert (wrong["ok"], wrong["error"]) == (False, "login_failed")

    done = call(server, "setup_login", email="me@example.com", code="123456").structured_content
    assert done == {"ok": True, "authenticated": True, "daemon_reloaded": False}
    assert config.load_credentials().email == "me@example.com"


def test_resources_serve_status_map_and_dashboard(server, daemon):
    def read(uri):
        return list(asyncio.run(server.read_resource(uri)))[0]

    assert json.loads(read("roborock://status").content)["battery"] == 100
    assert read("roborock://map.png").content == PNG
    page = read("ui://dashboard")
    assert page.mime_type == "text/html;profile=mcp-app" and "<canvas" in page.content
