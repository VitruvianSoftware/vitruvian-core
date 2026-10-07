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
import stat

import pytest

from vitruvian_roborock.core import config

from conftest import USER_DATA


def mode(path) -> int:
    return stat.S_IMODE(path.stat().st_mode)


def test_default_location_is_under_xdg_config(isolated_home):
    assert config.credentials_path() == isolated_home / ".config" / "vitruvian" / "roborock" / "credentials.json"


def test_xdg_config_home_is_honoured(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / "xdg"))
    assert config.config_dir() == tmp_path / "xdg" / "vitruvian" / "roborock"


def test_saved_credentials_are_private_and_round_trip():
    path = config.save_credentials(
        config.Credentials(email="me@example.com", user_data=USER_DATA, base_url="https://usiot")
    )
    assert mode(path) == 0o600
    assert mode(path.parent) == 0o700
    loaded = config.load_credentials()
    assert (loaded.email, loaded.user_data, loaded.base_url) == ("me@example.com", USER_DATA, "https://usiot")
    assert not list(path.parent.glob(".credentials.json.*")), "temp file left behind"


def test_loading_tightens_a_file_someone_loosened(logged_in):
    path = config.credentials_path()
    path.chmod(0o644)
    config.load_credentials()
    assert mode(path) == 0o600


def test_no_login_anywhere_is_none_not_an_error():
    assert config.load_credentials() is None


@pytest.mark.parametrize("key", ["userData", "user_data"])
def test_legacy_roborock_file_is_migrated_and_left_in_place(key):
    legacy = config.legacy_credentials_path()
    legacy.write_text(json.dumps({key: USER_DATA, "email": "me@example.com", "cacheData": {"homeData": {}}}))
    before = legacy.read_text()

    loaded = config.load_credentials()

    assert loaded.email == "me@example.com"
    assert loaded.user_data == USER_DATA
    assert loaded.migrated_from == str(legacy)
    assert mode(config.credentials_path()) == 0o600
    assert "cacheData" not in config.credentials_path().read_text(), "only the login is copied, not the cache"
    assert legacy.read_text() == before


def test_existing_credentials_win_over_legacy_file(logged_in):
    config.legacy_credentials_path().write_text(json.dumps({"userData": USER_DATA, "email": "other@example.com"}))
    assert config.load_credentials().email == "me@example.com"


@pytest.mark.parametrize(
    "content",
    [
        "not json",
        "[]",
        json.dumps({"email": "me@example.com"}),
        json.dumps({"userData": {"token": "x"}, "email": "me@example.com"}),
    ],
)
def test_unusable_legacy_file_is_ignored(content):
    config.legacy_credentials_path().write_text(content)
    assert config.load_credentials() is None
    assert not config.credentials_path().exists()


def test_migration_can_be_switched_off():
    config.legacy_credentials_path().write_text(json.dumps({"userData": USER_DATA, "email": "me@example.com"}))
    assert config.load_credentials(migrate=False) is None


@pytest.mark.parametrize("content", ["{", json.dumps({"email": "me@example.com"}), json.dumps([1])])
def test_corrupt_credentials_raise_config_error(content):
    config.ensure_private_dir(config.config_dir())
    config.credentials_path().write_text(content)
    with pytest.raises(config.ConfigError):
        config.load_credentials()


def test_unknown_fields_survive_a_rewrite(logged_in):
    path = config.credentials_path()
    doc = json.loads(path.read_text())
    doc["added_by_a_newer_version"] = {"x": 1}
    path.write_text(json.dumps(doc))
    config.save_credentials(config.load_credentials())
    assert json.loads(path.read_text())["added_by_a_newer_version"] == {"x": 1}


def test_token_is_created_once_private_and_stable():
    assert config.read_token() is None
    token = config.load_or_create_token()
    assert len(token) >= 32
    assert mode(config.token_path()) == 0o600
    assert config.load_or_create_token() == token == config.read_token()


def test_port_comes_from_env_and_is_validated(monkeypatch):
    assert config.daemon_port() == 8765
    monkeypatch.setenv(config.PORT_ENV, "9000")
    assert config.daemon_port() == 9000
    for bad in ("abc", "0", "70000"):
        monkeypatch.setenv(config.PORT_ENV, bad)
        with pytest.raises(config.ConfigError):
            config.daemon_port()


def test_email_is_masked_for_display():
    assert config.mask_email("james@example.com") == "j***@example.com"
    assert config.mask_email("nonsense") == "***"
