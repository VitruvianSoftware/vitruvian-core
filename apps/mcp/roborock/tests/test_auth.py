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

from vitruvian_roborock.core import auth, config

from conftest import USER_DATA


class RoborockInvalidCode(Exception):
    """Named like python-roborock's exception: the flow explains failures by class name."""


class FakeApi:
    def __init__(self, email: str, log: list) -> None:
        self.email = email
        self.log = log
        self.fail_request: Exception | None = None

    async def request_code_v4(self) -> None:
        if self.fail_request:
            raise self.fail_request
        self.log.append(("request", self.email, id(self)))

    async def code_login_v4(self, code):
        self.log.append(("login", self.email, id(self), code))
        if code != "123456":
            raise RoborockInvalidCode("bad code")
        return dict(USER_DATA)

    @property
    async def base_url(self) -> str:
        return "https://usiot.roborock.com"


@pytest.fixture
def flow():
    log: list = []
    made: list[FakeApi] = []

    def factory(email: str) -> FakeApi:
        made.append(FakeApi(email, log))
        return made[-1]

    flow = auth.LoginFlow(client_factory=factory)
    flow.log, flow.made = log, made
    return flow


def test_logged_out_status_carries_the_setup_hint():
    status = auth.auth_status().as_dict()
    assert status == {"authenticated": False, "hint": auth.SETUP_HINT}
    with pytest.raises(auth.NotAuthenticatedError, match="rrctl setup"):
        auth.require_credentials()


def test_logged_in_status_masks_the_email(logged_in):
    status = auth.auth_status().as_dict()
    assert status["authenticated"] is True
    assert status["email"] == "m***@example.com"
    assert "hint" not in status


def test_corrupt_credentials_read_as_logged_out_not_a_crash():
    config.ensure_private_dir(config.config_dir())
    config.credentials_path().write_text("{")
    status = auth.auth_status()
    assert status.authenticated is False and status.error
    with pytest.raises(auth.NotAuthenticatedError):
        auth.require_credentials()


def test_code_flow_stores_a_login_using_the_client_that_requested_the_code(flow):
    async def scenario():
        await flow.request_code("  Me@Example.com ")
        return await flow.complete("me@example.com", " 123 456 ")

    credentials = asyncio.run(scenario())

    assert len(flow.made) == 1, "login must reuse the requesting client; Roborock binds the code to it"
    assert flow.log[1][3] == "123456"
    stored = config.load_credentials()
    assert stored.email == credentials.email == "me@example.com"
    assert stored.user_data == USER_DATA
    assert stored.base_url == "https://usiot.roborock.com"


def test_wrong_code_is_explained_and_can_be_retried(flow):
    async def scenario():
        await flow.request_code("me@example.com")
        with pytest.raises(auth.AuthError, match="wrong or has expired"):
            await flow.complete("me@example.com", "000000")
        assert config.load_credentials() is None
        await flow.complete("me@example.com", "123456")

    asyncio.run(scenario())
    assert config.load_credentials() is not None


def test_completing_without_requesting_first_is_refused(flow):
    with pytest.raises(auth.AuthError, match="Request one first"):
        asyncio.run(flow.complete("me@example.com", "123456"))
    assert flow.made == []


@pytest.mark.parametrize("code", ["", "12ab", "one two"])
def test_non_numeric_code_never_reaches_roborock(flow, code):
    async def scenario():
        await flow.request_code("me@example.com")
        with pytest.raises(auth.AuthError, match="number"):
            await flow.complete("me@example.com", code)

    asyncio.run(scenario())
    assert [entry[0] for entry in flow.log] == ["request"]


def test_bad_email_is_refused_before_any_request(flow):
    with pytest.raises(auth.AuthError, match="valid email"):
        asyncio.run(flow.request_code("not-an-email"))
    assert flow.made == []


def test_unrecognised_failure_keeps_the_original_message():
    def factory(email):
        api = FakeApi(email, [])
        api.fail_request = RuntimeError("socket closed")
        return api

    with pytest.raises(auth.AuthError, match="socket closed"):
        asyncio.run(auth.LoginFlow(client_factory=factory).request_code("me@example.com"))
