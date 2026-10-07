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

from types import SimpleNamespace

import pytest

from vitruvian_roborock.core import config
from vitruvian_roborock.core.device import DeviceError, RoborockVacuum, UnknownActionError, resolve_rooms

from conftest import USER_DATA

ROOMS = [{"id": 16, "name": "Kitchen"}, {"id": 17, "name": "Living Room"}]


def make(in_cleaning=0, **status):
    vacuum = RoborockVacuum(config.Credentials(email="me@example.com", user_data=USER_DATA))
    fields = dict(
        state=SimpleNamespace(value=8),
        state_name="charging",
        battery=87,
        error_code=SimpleNamespace(value=0),
        error_code_name="none",
        dock_error_status=None,
        clean_time=600,
        square_meter_clean_area=12.5,
        clean_percent=None,
        in_cleaning=in_cleaning,
        in_returning=0,
        fan_speed_name="balanced",
        water_mode_name=None,
        mop_route_name=None,
    )
    fields.update(status)
    vacuum._props = SimpleNamespace(status=SimpleNamespace(**fields))
    vacuum._device = SimpleNamespace(
        duid="duid-1", name="Rocky", product=SimpleNamespace(model="a70"), is_local_connected=True
    )
    vacuum._rooms = list(ROOMS)
    return vacuum


def test_rooms_resolve_by_name_ignoring_case_or_by_id_without_duplicates():
    assert resolve_rooms(["kitchen", "LIVING ROOM", "16", 17], ROOMS) == [16, 17]


def test_unknown_room_lists_what_is_available():
    with pytest.raises(DeviceError, match="Unknown room 'Garage'. Available: Kitchen, Living Room"):
        resolve_rooms(["Garage"], ROOMS)
    with pytest.raises(DeviceError, match="Unknown room '99'"):
        resolve_rooms(["99"], ROOMS)


def test_no_rooms_is_an_error_not_a_whole_home_clean():
    with pytest.raises(DeviceError, match="at least one room"):
        resolve_rooms([], ROOMS)


@pytest.mark.parametrize(
    ("action", "raw"),
    [
        ("start", "app_start"),
        ("pause", "app_pause"),
        ("stop", "app_stop"),
        ("dock", "app_charge"),
        ("find", "find_me"),
        ("wash_start", "app_start_wash"),
        ("wash_stop", "app_stop_wash"),
    ],
)
def test_simple_actions_map_to_roborock_commands(action, raw):
    assert make()._resolve(action, {}) == (raw, None)


@pytest.mark.parametrize(
    ("in_cleaning", "raw"), [(0, "app_start"), (1, "app_start"), (2, "resume_zoned_clean"), (3, "resume_segment_clean")]
)
def test_resume_continues_the_kind_of_clean_that_was_paused(in_cleaning, raw):
    assert make(in_cleaning=in_cleaning)._resolve("resume", {}) == (raw, None)
    assert make(in_cleaning=SimpleNamespace(value=in_cleaning))._resolve("resume", {}) == (raw, None)


def test_clean_rooms_builds_a_segment_clean():
    assert make()._resolve("clean_rooms", {"rooms": ["Kitchen"], "repeat": 2}) == (
        "app_segment_clean",
        [{"segments": [16], "repeat": 2}],
    )
    with pytest.raises(DeviceError, match="repeat"):
        make()._resolve("clean_rooms", {"rooms": ["Kitchen"], "repeat": 9})


def test_unknown_action_is_refused_by_name():
    with pytest.raises(UnknownActionError, match="Unknown action 'explode'"):
        make()._resolve("explode", {})


def test_snapshot_reports_no_error_when_the_code_is_zero():
    snapshot = make()._snapshot()
    assert snapshot["error"] is None and snapshot["error_code"] is None
    assert (snapshot["state"], snapshot["state_code"], snapshot["battery"]) == ("charging", 8, 87)
    assert snapshot["device"] == {"id": "duid-1", "name": "Rocky", "model": "a70", "local": True}
    assert snapshot["rooms"] == ROOMS


def test_snapshot_reports_a_real_error():
    snapshot = make(error_code=SimpleNamespace(value=5), error_code_name="main brush jammed")._snapshot()
    assert (snapshot["error"], snapshot["error_code"]) == ("main brush jammed", 5)


def test_snapshot_survives_a_label_that_cannot_be_computed():
    class Status(SimpleNamespace):
        @property
        def fan_speed_name(self):
            raise KeyError("device features not loaded")

    vacuum = make()
    fields = {k: v for k, v in vars(vacuum._props.status).items() if k != "fan_speed_name"}
    vacuum._props = SimpleNamespace(status=Status(**fields))
    assert vacuum._snapshot()["fan_speed"] is None


def test_calls_before_connect_fail_clearly():
    import asyncio

    vacuum = RoborockVacuum(config.Credentials(email="me@example.com", user_data=USER_DATA))
    with pytest.raises(DeviceError, match="Not connected"):
        asyncio.run(vacuum.command("pause"))


def pick(vacuum, devices):
    return vacuum._select(devices)


def test_device_selection():
    v1 = SimpleNamespace(duid="a", name="Rocky", v1_properties=object())
    other = SimpleNamespace(duid="b", name="Dyad", v1_properties=None)
    creds = config.Credentials(email="me@example.com", user_data=USER_DATA)
    assert pick(RoborockVacuum(creds), [other, v1]) is v1
    assert pick(RoborockVacuum(creds, device_id="Rocky"), [other, v1]) is v1
    assert pick(RoborockVacuum(creds, device_id="a"), [other, v1]) is v1
    with pytest.raises(DeviceError, match="does not support yet"):
        pick(RoborockVacuum(creds, device_id="Dyad"), [other, v1])
    with pytest.raises(DeviceError, match="No device named"):
        pick(RoborockVacuum(creds, device_id="nope"), [v1])
    with pytest.raises(DeviceError, match="no devices"):
        pick(RoborockVacuum(creds), [])
    with pytest.raises(DeviceError, match="does not support yet"):
        pick(RoborockVacuum(creds), [other])


def test_stored_login_is_readable_by_python_roborock():
    """The credentials file holds python-roborock's own format; prove the library still parses it."""
    data = pytest.importorskip("roborock.data")
    user_data = data.UserData.from_dict(USER_DATA)
    assert user_data.rriot.u == "user"
    assert data.UserData.from_dict(user_data.as_dict()).rriot.r.m == "ssl://m"
