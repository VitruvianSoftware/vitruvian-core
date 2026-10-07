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

"""Roborock cloud login by emailed verification code (the v4 flow).

Login is two steps that must share one API client: Roborock ties the emailed
code to the client id that asked for it. `LoginFlow` keeps that client between
the steps, so it has to live as long as the process that started the login.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from typing import Any, Protocol

from vitruvian_roborock.core import config

SETUP_HINT = "Not logged in to Roborock. Run `rrctl setup`, or call the setup_login tool with your account email."


class AuthError(Exception):
    """Login failed for a reason the user can act on."""


class NotAuthenticatedError(AuthError):
    """There is no stored login."""

    def __init__(self, message: str = SETUP_HINT) -> None:
        super().__init__(message)


class _ApiClient(Protocol):
    """The slice of `roborock.web_api.RoborockApiClient` the flow uses."""

    async def request_code_v4(self) -> None: ...

    async def code_login_v4(self, code: int | str) -> Any: ...


ClientFactory = Callable[[str], _ApiClient]


def _roborock_client(email: str) -> _ApiClient:
    from roborock.web_api import RoborockApiClient

    return RoborockApiClient(username=email)


def _explain(err: Exception) -> str:
    """Turn a python-roborock failure into one sentence for the user."""
    hints = {
        "RoborockAccountDoesNotExist": "No Roborock account uses that email address.",
        "RoborockInvalidEmail": "That is not a valid email address.",
        "RoborockInvalidCode": "That verification code is wrong or has expired. Request a new one.",
        "RoborockTooFrequentCodeRequests": "A code was requested too recently. Wait a minute and try again.",
        "RoborockRateLimit": "Roborock is rate limiting logins from here. Try again later.",
        "RoborockTooManyRequest": "Roborock is rate limiting logins from here. Try again later.",
        "RoborockInvalidUserAgreement": "Accept the latest user agreement in the Roborock app, then try again.",
        "RoborockNoUserAgreement": "Accept the user agreement in the Roborock app, then try again.",
        "RoborockNoResponseFromBaseURL": "Could not reach the Roborock cloud. Check the network and try again.",
        "RoborockUrlException": "Could not find the Roborock region for that account.",
    }
    return hints.get(type(err).__name__) or f"Roborock login failed: {err}"


@dataclass
class AuthStatus:
    authenticated: bool
    email: str | None = None
    credentials_path: str | None = None
    migrated_from: str | None = None
    error: str | None = None

    def as_dict(self) -> dict[str, Any]:
        doc: dict[str, Any] = {"authenticated": self.authenticated}
        if self.email:
            doc["email"] = config.mask_email(self.email)
        if self.credentials_path:
            doc["credentials_path"] = self.credentials_path
        if self.migrated_from:
            doc["migrated_from"] = self.migrated_from
        if self.error:
            doc["error"] = self.error
        if not self.authenticated:
            doc["hint"] = SETUP_HINT
        return doc


def auth_status() -> AuthStatus:
    """Whether a login is stored. Never raises: a broken file reads as logged out."""
    try:
        credentials = config.load_credentials()
    except config.ConfigError as err:
        return AuthStatus(authenticated=False, error=str(err))
    if credentials is None:
        return AuthStatus(authenticated=False)
    return AuthStatus(
        authenticated=True,
        email=credentials.email,
        credentials_path=str(config.credentials_path()),
        migrated_from=credentials.migrated_from,
    )


def require_credentials() -> config.Credentials:
    try:
        credentials = config.load_credentials()
    except config.ConfigError as err:
        raise NotAuthenticatedError(f"{err}. Run `rrctl setup` to log in again.") from err
    if credentials is None:
        raise NotAuthenticatedError()
    return credentials


class LoginFlow:
    """Request a code, then trade it for a stored login."""

    def __init__(self, client_factory: ClientFactory | None = None) -> None:
        self._client_factory = client_factory or _roborock_client
        self._pending: dict[str, _ApiClient] = {}

    async def request_code(self, email: str) -> None:
        email = _normalise(email)
        client = self._client_factory(email)
        try:
            await client.request_code_v4()
        except Exception as err:
            raise AuthError(_explain(err)) from err
        self._pending[email] = client

    async def complete(self, email: str, code: str) -> config.Credentials:
        email = _normalise(email)
        code = "".join(str(code).split())
        if not code.isdigit():
            raise AuthError("The verification code is the number Roborock emailed you.")
        client = self._pending.get(email)
        if client is None:
            raise AuthError("No code has been requested for that email in this session. Request one first.")
        try:
            user_data = await client.code_login_v4(code)
            base_url = await _base_url(client)
        except Exception as err:
            raise AuthError(_explain(err)) from err
        credentials = config.Credentials(email=email, user_data=_serialise(user_data), base_url=base_url)
        config.save_credentials(credentials)
        del self._pending[email]
        return credentials


def _normalise(email: str) -> str:
    email = email.strip().lower()
    if "@" not in email:
        raise AuthError("That is not a valid email address.")
    return email


def _serialise(user_data: Any) -> dict[str, Any]:
    if isinstance(user_data, dict):
        return user_data
    return user_data.as_dict()


async def _base_url(client: Any) -> str | None:
    """The region endpoint the login resolved to; saving it skips rediscovery on every connect."""
    base_url = getattr(client, "base_url", None)
    if base_url is None:
        return None
    if isinstance(base_url, str):
        return base_url
    return await base_url
