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

import json

import pytest

from vitruvian_roborock import __version__
from vitruvian_roborock.cli import commands, main
from vitruvian_roborock.core import auth, config
from vitruvian_roborock.daemon.client import DaemonRequestError, DaemonUnavailable

from conftest import PNG, STATUS


class FakeClient:
    base_url = "http://127.0.0.1:8765"
    port = 8765

    def __init__(self) -> None:
        self.doc = {"authenticated": True, "connected": True, **STATUS}
        self.png: bytes | None = PNG
        self.sent: list = []
        self.refuse: Exception | None = None

    def status(self):
        return self.doc

    def map_png(self):
        return self.png

    def command(self, action, params=None):
        if self.refuse:
            raise self.refuse
        self.sent.append(action)
        return {"ok": True}


@pytest.fixture
def daemon(monkeypatch):
    fake = FakeClient()
    monkeypatch.setattr(commands.daemon_client, "ensure_running", lambda port=None: fake)
    return fake


def test_every_agreed_command_exists():
    parser = main.build_parser()
    for argv in (["setup"], ["status"], ["map"], ["pause"], ["resume"], ["dock"], ["daemon"], ["mcp"], ["dashboard"]):
        assert callable(parser.parse_args(argv).run), argv
    assert parser.parse_args(["daemon"]).daemon_action == "run"
    assert parser.parse_args(["--port", "9000", "daemon", "start"]).port == 9000


def test_version_and_unknown_command(capsys):
    with pytest.raises(SystemExit) as shown:
        main.main(["--version"])
    assert shown.value.code == 0 and __version__ in capsys.readouterr().out
    with pytest.raises(SystemExit) as refused:
        main.main(["explode"])
    assert refused.value.code == 2


def test_status_prints_a_summary(daemon, capsys):
    assert main.main(["status"]) == 0
    out = capsys.readouterr().out
    assert "Rocky: charging" in out and "battery   100%" in out and "Kitchen, Living Room" in out


def test_status_json_is_the_raw_document(daemon, capsys):
    assert main.main(["status", "--json"]) == 0
    assert json.loads(capsys.readouterr().out) == daemon.doc


def test_status_when_logged_out_says_how_to_fix_it_and_fails(daemon, capsys):
    daemon.doc = {"authenticated": False, "connected": False, "hint": auth.SETUP_HINT}
    assert main.main(["status"]) == 1
    assert "rrctl setup" in capsys.readouterr().out


def test_status_when_unreachable_fails_with_the_reason(daemon, capsys):
    daemon.doc = {"authenticated": True, "connected": False, "error": "cloud unreachable"}
    assert main.main(["status"]) == 1
    assert "cloud unreachable" in capsys.readouterr().out


@pytest.mark.parametrize(("argv", "action"), [("pause", "pause"), ("resume", "resume"), ("dock", "dock")])
def test_action_commands(daemon, argv, action):
    assert main.main([argv]) == 0
    assert daemon.sent == [action]


def test_a_refused_action_is_one_line_on_stderr(daemon, capsys):
    daemon.refuse = DaemonRequestError(409, {"error": "not_authenticated", "message": "Not logged in to Roborock."})
    assert main.main(["pause"]) == 1
    captured = capsys.readouterr()
    assert captured.err == "rrctl: Not logged in to Roborock.\n" and captured.out == ""


def test_daemon_that_cannot_start_is_reported(monkeypatch, capsys):
    def cannot(port=None):
        raise DaemonUnavailable("The daemon did not start on port 8765.")

    monkeypatch.setattr(commands.daemon_client, "ensure_running", cannot)
    assert main.main(["status"]) == 1
    assert "did not start" in capsys.readouterr().err


def test_map_writes_the_png(daemon, tmp_path, capsys):
    target = tmp_path / "m.png"
    assert main.main(["map", "-o", str(target)]) == 0
    assert target.read_bytes() == PNG
    daemon.png = None
    assert main.main(["map", "-o", str(target)]) == 1
    assert "not sent a map yet" in capsys.readouterr().err


def test_dashboard_url_carries_the_token_in_the_fragment_only(daemon, capsys):
    token = config.load_or_create_token()
    assert main.main(["dashboard", "--no-open"]) == 0
    url = capsys.readouterr().out.strip()
    assert url == f"http://127.0.0.1:8765/#token={token}"
    assert "?" not in url


def test_setup_is_a_no_op_when_already_logged_in(logged_in, capsys):
    assert main.main(["setup"]) == 0
    out = capsys.readouterr().out
    assert "Already logged in as m***@example.com" in out


def test_setup_runs_the_code_flow(monkeypatch, capsys):
    from conftest import USER_DATA

    class Api:
        async def request_code_v4(self):
            pass

        async def code_login_v4(self, code):
            assert code == "123456"
            return dict(USER_DATA)

    monkeypatch.setattr(auth, "_roborock_client", lambda email: Api())
    monkeypatch.setattr("builtins.input", lambda prompt="": "123456")
    monkeypatch.setattr(commands.DaemonClient, "health", lambda self: None)
    assert main.main(["setup", "--email", "me@example.com"]) == 0
    assert config.load_credentials().email == "me@example.com"
    assert "Logged in" in capsys.readouterr().out


def test_daemon_status_and_stop_when_nothing_is_running(monkeypatch, capsys):
    monkeypatch.setattr(commands.DaemonClient, "health", lambda self: None)
    assert main.main(["daemon", "status"]) == 1
    assert main.main(["daemon", "stop"]) == 0
    assert "not running" in capsys.readouterr().out
