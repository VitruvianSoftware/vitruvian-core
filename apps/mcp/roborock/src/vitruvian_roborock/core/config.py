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

"""Paths, credential storage and legacy migration.

Standard library only: every other layer imports this, including the ones that
must work before python-roborock is importable or the user has logged in.
"""

from __future__ import annotations

import json
import os
import secrets
import stat
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

DAEMON_HOST = "127.0.0.1"
DEFAULT_DAEMON_PORT = 8765

HOME_ENV = "VITRUVIAN_ROBOROCK_HOME"
PORT_ENV = "VITRUVIAN_ROBOROCK_PORT"
DEVICE_ENV = "VITRUVIAN_ROBOROCK_DEVICE"

CREDENTIALS_VERSION = 1
_PRIVATE_FILE = 0o600
_PRIVATE_DIR = 0o700


def config_dir() -> Path:
    """`~/.config/vitruvian/roborock`, honouring `XDG_CONFIG_HOME`."""
    override = os.environ.get(HOME_ENV)
    if override:
        return Path(override).expanduser()
    base = os.environ.get("XDG_CONFIG_HOME") or "~/.config"
    return Path(base).expanduser() / "vitruvian" / "roborock"


def credentials_path() -> Path:
    return config_dir() / "credentials.json"


def token_path() -> Path:
    return config_dir() / "daemon-token"


def cache_path() -> Path:
    return config_dir() / "cache" / "home.pickle"


def log_path() -> Path:
    return config_dir() / "daemon.log"


def legacy_credentials_path() -> Path:
    """Where python-roborock's own `roborock` CLI keeps its login."""
    return Path("~/.roborock").expanduser()


def daemon_port() -> int:
    raw = os.environ.get(PORT_ENV)
    if not raw:
        return DEFAULT_DAEMON_PORT
    try:
        port = int(raw)
    except ValueError as err:
        raise ConfigError(f"{PORT_ENV} must be a port number, got {raw!r}") from err
    if not 0 < port < 65536:
        raise ConfigError(f"{PORT_ENV} must be between 1 and 65535, got {port}")
    return port


class ConfigError(Exception):
    """The on-disk configuration is unusable."""


@dataclass
class Credentials:
    """A Roborock cloud login.

    `user_data` is python-roborock's `UserData` in its own serialised form. It is
    kept opaque here so this module never needs the library to read or write it.
    """

    email: str
    user_data: dict[str, Any]
    base_url: str | None = None
    migrated_from: str | None = None
    extra: dict[str, Any] = field(default_factory=dict)

    def to_json(self) -> dict[str, Any]:
        doc: dict[str, Any] = {
            **self.extra,
            "version": CREDENTIALS_VERSION,
            "email": self.email,
            "user_data": self.user_data,
        }
        if self.base_url:
            doc["base_url"] = self.base_url
        if self.migrated_from:
            doc["migrated_from"] = self.migrated_from
        return doc

    @classmethod
    def from_json(cls, doc: Any) -> Credentials:
        if not isinstance(doc, dict):
            raise ConfigError("credentials file is not a JSON object")
        email = doc.get("email")
        user_data = doc.get("user_data")
        if not isinstance(email, str) or not email or not isinstance(user_data, dict) or not user_data:
            raise ConfigError("credentials file is missing 'email' or 'user_data'")
        known = {"version", "email", "user_data", "base_url", "migrated_from"}
        return cls(
            email=email,
            user_data=user_data,
            base_url=doc.get("base_url") or None,
            migrated_from=doc.get("migrated_from") or None,
            extra={k: v for k, v in doc.items() if k not in known},
        )


def ensure_private_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    if stat.S_IMODE(path.stat().st_mode) != _PRIVATE_DIR:
        path.chmod(_PRIVATE_DIR)
    return path


def write_private(path: Path, data: bytes) -> None:
    """Write `data` so it is never readable by another user, even briefly.

    The temp file is created 0600 before any byte lands in it, then renamed over
    the target, so a crash leaves either the old file or the new one.
    """
    ensure_private_dir(path.parent)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        os.fchmod(fd, _PRIVATE_FILE)
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def _tighten(path: Path) -> None:
    if stat.S_IMODE(path.stat().st_mode) != _PRIVATE_FILE:
        path.chmod(_PRIVATE_FILE)


def save_credentials(credentials: Credentials) -> Path:
    path = credentials_path()
    write_private(path, (json.dumps(credentials.to_json(), indent=2) + "\n").encode())
    return path


def load_credentials(*, migrate: bool = True) -> Credentials | None:
    """Return the stored login, or None when the user has not set one up.

    With `migrate`, a login left by python-roborock's CLI in `~/.roborock` is
    copied into our own file the first time it is needed. The original is left
    alone: the upstream CLI still reads it.
    """
    path = credentials_path()
    if path.is_file():
        _tighten(path)
        try:
            doc = json.loads(path.read_text())
        except (OSError, ValueError) as err:
            raise ConfigError(f"cannot read {path}: {err}") from err
        return Credentials.from_json(doc)
    if migrate:
        return migrate_legacy_credentials()
    return None


def migrate_legacy_credentials() -> Credentials | None:
    """Copy `~/.roborock` into our credentials file. None if there is nothing usable."""
    legacy = legacy_credentials_path()
    if not legacy.is_file():
        return None
    try:
        doc = json.loads(legacy.read_text())
    except (OSError, ValueError):
        return None
    if not isinstance(doc, dict):
        return None
    # python-roborock has written this file with both key styles over time.
    user_data = doc.get("userData") or doc.get("user_data")
    email = doc.get("email")
    if not isinstance(user_data, dict) or not user_data.get("rriot") or not isinstance(email, str) or not email:
        return None
    credentials = Credentials(email=email, user_data=user_data, migrated_from=str(legacy))
    save_credentials(credentials)
    return credentials


def clear_credentials() -> bool:
    path = credentials_path()
    if path.is_file():
        path.unlink()
        return True
    return False


def load_or_create_token() -> str:
    """The shared secret between the daemon and its local clients."""
    path = token_path()
    if path.is_file():
        _tighten(path)
        token = path.read_text().strip()
        if token:
            return token
    token = secrets.token_urlsafe(32)
    write_private(path, (token + "\n").encode())
    return token


def read_token() -> str | None:
    path = token_path()
    if not path.is_file():
        return None
    return path.read_text().strip() or None


def mask_email(email: str) -> str:
    name, _, domain = email.partition("@")
    if not domain:
        return "***"
    return f"{name[:1]}***@{domain}"
