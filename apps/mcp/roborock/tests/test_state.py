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

import pytest

from vitruvian_roborock.core import auth
from vitruvian_roborock.daemon.state import ServiceUnavailable, StateStore, VacuumService

from conftest import PNG, until


def service_for(vacuum, store=None, **kwargs):
    store = store or StateStore()
    kwargs.setdefault("backoff_initial", 0.01)
    return store, VacuumService(store, lambda credentials: vacuum, **kwargs)


def test_store_only_announces_real_changes():
    store = StateStore()
    queue = store.subscribe()
    assert store.set_status({"connected": True, "battery": 50, "updated_at": 1}) is True
    assert store.set_status({"connected": True, "battery": 50, "updated_at": 2}) is False
    assert store.set_status({"connected": True, "battery": 49, "updated_at": 3}) is True
    assert queue.qsize() == 2
    assert store.status["updated_at"] == 3


def test_map_version_moves_only_when_the_image_does():
    store = StateStore()
    queue = store.subscribe()
    assert store.set_map(None) is False
    assert store.set_map(PNG) is True
    assert store.set_map(PNG) is False
    assert store.set_map(PNG + b"x") is True
    assert (store.map_version, store.status["map_version"]) == (2, 2)
    assert [queue.get_nowait() for _ in range(2)] == [("map", {"version": 1}), ("map", {"version": 2})]


def test_a_stalled_subscriber_loses_old_events_not_new_ones():
    store = StateStore()
    queue = store.subscribe()
    for battery in range(100):
        store.set_status({"battery": battery})
    assert queue.qsize() == queue.maxsize
    events = [queue.get_nowait() for _ in range(queue.qsize())]
    assert events[-1][1]["battery"] == 99


def test_unsubscribed_queues_hear_nothing_and_close_ends_streams():
    store = StateStore()
    gone, staying = store.subscribe(), store.subscribe()
    store.unsubscribe(gone)
    store.close()
    assert gone.empty()
    assert staying.get_nowait() is None


def test_without_a_login_the_service_reports_it_and_refuses_commands(vacuum):
    async def scenario():
        store, service = service_for(vacuum)
        await service.start()
        await until(lambda: "hint" in store.status)
        assert store.status["authenticated"] is False
        assert store.status["hint"] == auth.SETUP_HINT
        assert vacuum.connects == 0
        with pytest.raises(ServiceUnavailable) as refused:
            await service.command("pause")
        assert refused.value.code == "not_authenticated"
        await service.stop()

    asyncio.run(scenario())


def test_connects_polls_and_publishes_status_and_map(logged_in, vacuum):
    async def scenario():
        store, service = service_for(vacuum)
        await service.start()
        await until(lambda: store.map_png is not None)
        status = store.status
        assert (status["authenticated"], status["connected"], status["state"]) == (True, True, "charging")
        assert status["map_version"] == 1 and store.map_png == PNG
        await service.stop()
        assert vacuum.closed == 1

    asyncio.run(scenario())


def test_command_reaches_the_vacuum_and_triggers_an_immediate_refresh(logged_in, vacuum):
    async def scenario():
        store, service = service_for(vacuum, poll_parked=60)
        await service.start()
        await until(lambda: store.status.get("connected"))
        vacuum.snapshot = {**vacuum.snapshot, "state": "cleaning", "state_code": 5}
        assert await service.command("clean_rooms", {"rooms": ["Kitchen"]}) == ["ok"]
        assert vacuum.commands == [("clean_rooms", {"rooms": ["Kitchen"]})]
        # With a 60s poll, only the post-command wake-up can deliver this in time.
        await until(lambda: store.status["state"] == "cleaning")
        await service.stop()

    asyncio.run(scenario())


def test_failed_connect_is_reported_then_retried(logged_in, vacuum):
    async def scenario():
        vacuum.fail_connect = 2
        store, service = service_for(vacuum)
        await service.start()
        await until(lambda: store.status.get("error") == "cloud unreachable")
        assert store.status["authenticated"] is True and store.status["connected"] is False
        with pytest.raises(ServiceUnavailable) as refused:
            await service.command("pause")
        assert refused.value.code == "not_connected"
        await until(lambda: store.status.get("connected"))
        assert vacuum.connects == 3
        await service.stop()

    asyncio.run(scenario())


def test_a_failed_poll_keeps_last_known_state_and_recovers(logged_in, vacuum):
    async def scenario():
        store, service = service_for(vacuum, poll_parked=0.01)
        await service.start()
        await until(lambda: store.status.get("connected"))
        vacuum.fail_status = True
        await until(lambda: store.status["connected"] is False)
        assert store.status["error"] == "no answer"
        assert store.status["state"] == "charging", "last known state stays visible"
        vacuum.fail_status = False
        await until(lambda: store.status["connected"] is True)
        assert store.status["error"] is None
        assert vacuum.connects == 1, "the library reconnects itself; we must not tear down"
        await service.stop()

    asyncio.run(scenario())


def test_rejected_login_stops_the_loop_and_asks_for_setup(logged_in, vacuum):
    async def scenario():
        store, service = service_for(vacuum, poll_parked=0.01)
        await service.start()
        await until(lambda: store.status.get("connected"))
        vacuum.credentials_rejected = True
        await until(lambda: store.status["authenticated"] is False)
        assert "rejected" in store.status["error"]
        with pytest.raises(ServiceUnavailable) as refused:
            await service.command("pause")
        assert refused.value.code == "not_authenticated"
        connects = vacuum.connects
        await asyncio.sleep(0.05)
        assert vacuum.connects == connects, "must not hammer the cloud with a rejected login"
        await service.stop()

    asyncio.run(scenario())


def test_reload_picks_up_a_login_made_after_start(vacuum):
    async def scenario():
        from vitruvian_roborock.core import config

        from conftest import USER_DATA

        store, service = service_for(vacuum)
        await service.start()
        await until(lambda: "hint" in store.status)
        config.save_credentials(config.Credentials(email="me@example.com", user_data=USER_DATA))
        await service.reload()
        await until(lambda: store.status.get("connected"))
        assert "hint" not in store.status
        await service.stop()

    asyncio.run(scenario())


def test_pushed_updates_are_published_without_waiting_for_a_poll(logged_in, vacuum):
    async def scenario():
        store, service = service_for(vacuum, poll_parked=60)
        await service.start()
        await until(lambda: vacuum.listener is not None and store.status.get("connected"))
        vacuum.listener({**vacuum.snapshot, "battery": 42})
        assert store.status["battery"] == 42
        await service.stop()

    asyncio.run(scenario())
