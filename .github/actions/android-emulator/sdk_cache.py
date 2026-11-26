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

"""Cache metadata, verification, measurement, and pruning for Android emulator SDK packages."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

# Bump the v1 segment to drop a bad cache entry.
CACHE_SCHEMA_VERSION = "v1"

_API_LEVEL_RE = re.compile(r"^[0-9]+(\.[0-9]+)?$")
_SYSTEM_IMAGE_RE = re.compile(
    r"^system-images;[A-Za-z0-9._-]+;[A-Za-z0-9._-]+;[A-Za-z0-9._-]+$"
)
_TOKEN_RE = re.compile(r"^[A-Za-z0-9._-]+$")
_REVISION_RE = re.compile(r"^[0-9]+(\.[0-9]+)*(-rc[0-9]+)?$")
_RESOLVED_SUFFIX_RE = re.compile(
    r"^pt[0-9]+(?:\.[0-9]+)*(?:-rc[0-9]+)?"
    r"-emu[0-9]+(?:\.[0-9]+)*(?:-rc[0-9]+)?"
    r"-plat[0-9]+(?:\.[0-9]+)*(?:-rc[0-9]+)?"
    r"-img[0-9]+(?:\.[0-9]+)*(?:-rc[0-9]+)?$"
)


def validate_api_level(api_level: str) -> str:
    """Validate an Android API level string."""
    if not isinstance(api_level, str) or not _API_LEVEL_RE.fullmatch(api_level):
        raise ValueError(f"invalid api-level {api_level!r}")
    return api_level


def validate_system_image(system_image: str) -> str:
    """Validate an sdkmanager system-image coordinate."""
    if not isinstance(system_image, str) or not _SYSTEM_IMAGE_RE.fullmatch(
        system_image
    ):
        raise ValueError(f"invalid system-image coordinate {system_image!r}")
    for seg in system_image.split(";"):
        if seg in ("", ".", "..") or ".." in seg:
            raise ValueError(
                f"invalid segment in system-image coordinate {system_image!r}"
            )
    return system_image


def validate_token(value: str, label: str) -> str:
    """Validate a cache-key token such as runner OS or arch."""
    if not isinstance(value, str) or not _TOKEN_RE.fullmatch(value):
        raise ValueError(f"invalid {label} {value!r}")
    return value


def package_specs(api_level: str, system_image: str) -> list[tuple[str, str, str]]:
    """Return ordered `(short_tag, coordinate, rel_path)` specs for the 4 cached SDK packages."""
    api = validate_api_level(api_level)
    img = validate_system_image(system_image)
    return [
        ("pt", "platform-tools", "platform-tools"),
        ("emu", "emulator", "emulator"),
        ("plat", f"platforms;android-{api}", f"platforms/android-{api}"),
        ("img", img, img.replace(";", "/")),
    ]


def cached_rel_paths(api_level: str, system_image: str) -> list[str]:
    """Return all SDK-relative paths cached for the Android emulator."""
    return [rel for _tag, _coord, rel in package_specs(api_level, system_image)] + [
        "licenses"
    ]


def build_key_prefix(
    runner_os: str, runner_arch: str, api_level: str, system_image: str
) -> str:
    """Return the versioned Actions cache key prefix before resolved package revisions."""
    os_tok = validate_token(runner_os, "runner-os")
    arch_tok = validate_token(runner_arch, "runner-arch")
    api = validate_api_level(api_level)
    img = validate_system_image(system_image)
    slug = img.replace(";", "_")
    return f"android-emulator-sdk-{CACHE_SCHEMA_VERSION}-{os_tok}-{arch_tok}-api{api}-{slug}-rev-"


def matches_sdk_key_prefix(key: object, key_prefix: str) -> bool:
    """True when `key` belongs to `key_prefix` (delimited) with a valid resolved revision suffix."""
    if (
        not isinstance(key, str)
        or not isinstance(key_prefix, str)
        or not key
        or not key_prefix
    ):
        return False
    delimited = key_prefix if key_prefix.endswith("-") else f"{key_prefix}-"
    if not key.startswith(delimited):
        return False
    return bool(_RESOLVED_SUFFIX_RE.fullmatch(key[len(delimited) :]))


def build_resolved_key(prefix: str, revisions_by_tag: dict[str, str]) -> str:
    """Build the full exact cache key from prefix and resolved package revisions."""
    return (
        f"{prefix}pt{revisions_by_tag['pt']}-emu{revisions_by_tag['emu']}"
        f"-plat{revisions_by_tag['plat']}-img{revisions_by_tag['img']}"
    )


def _local_tag(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def read_package_xml_revision(package_xml_path: Path, expected_coordinate: str) -> str:
    """Parse `<localPackage path=...><revision>...</revision>` and return its version string."""
    if not package_xml_path.is_file():
        raise ValueError(f"missing package.xml at {package_xml_path}")
    try:
        tree = ET.parse(package_xml_path)
    except ET.ParseError as exc:
        raise ValueError(f"invalid XML in {package_xml_path}: {exc}") from exc

    root = tree.getroot()
    local_pkg = None
    for elem in root.iter():
        if _local_tag(elem.tag) == "localPackage":
            local_pkg = elem
            break
    if local_pkg is None:
        raise ValueError(f"missing <localPackage> in {package_xml_path}")

    found_path = local_pkg.attrib.get("path", "")
    if found_path != expected_coordinate:
        raise ValueError(
            f"package.xml path mismatch in {package_xml_path}: got {found_path!r}, expected {expected_coordinate!r}"
        )

    rev_elem = None
    for child in local_pkg:
        if _local_tag(child.tag) == "revision":
            rev_elem = child
            break
    if rev_elem is None:
        raise ValueError(f"missing <revision> in {package_xml_path}")

    fields: dict[str, str] = {}
    for child in rev_elem:
        name = _local_tag(child.tag)
        if child.text is not None:
            fields[name] = child.text.strip()

    if "major" not in fields or not fields["major"]:
        raise ValueError(f"missing <major> revision in {package_xml_path}")

    parts = [fields["major"]]
    if "minor" in fields and fields["minor"] != "":
        parts.append(fields["minor"])
        if "micro" in fields and fields["micro"] != "":
            parts.append(fields["micro"])
    version = ".".join(parts)
    if "preview" in fields and fields["preview"] != "":
        version = f"{version}-rc{fields['preview']}"

    if not _REVISION_RE.fullmatch(version):
        raise ValueError(f"invalid revision {version!r} in {package_xml_path}")
    return version


def _normalize_revision(version: str) -> str:
    """Normalize sdkmanager revision text (e.g. '37.1.11 rc2' -> '37.1.11-rc2')."""
    return re.sub(r"\s+rc([0-9]+)$", r"-rc\1", version.strip())


def parse_sdkmanager_list_installed(stdout_text: str) -> dict[str, str]:
    """Parse `sdkmanager --list_installed` output into `{coordinate: version}`."""
    installed: dict[str, str] = {}
    in_installed_section = False
    for raw_line in stdout_text.splitlines():
        stripped = raw_line.strip()
        if not stripped:
            continue
        if stripped == "Installed packages:":
            in_installed_section = True
            continue
        if in_installed_section and "|" not in raw_line:
            if stripped.startswith("Available "):
                break
            continue
        if "|" not in raw_line:
            continue
        cols = [c.strip() for c in raw_line.split("|")]
        if len(cols) < 2:
            continue
        coord, version = cols[0], cols[1]
        if not coord or coord == "Path" or set(coord) <= {"-"}:
            continue
        installed[coord] = _normalize_revision(version)
    return installed


def parse_sdkmanager_available_packages(stdout_text: str) -> dict[str, str]:
    """Parse `sdkmanager --list` Available Packages section into `{coordinate: version}`."""
    available: dict[str, str] = {}
    in_available_section = False
    for raw_line in stdout_text.splitlines():
        stripped = raw_line.strip()
        if not stripped:
            continue
        if "|" not in raw_line and stripped.endswith(":"):
            if stripped.lower() == "available packages:":
                in_available_section = True
                continue
            if in_available_section:
                break
            continue
        if not in_available_section or "|" not in raw_line:
            continue
        cols = [c.strip() for c in raw_line.split("|")]
        if len(cols) < 2:
            continue
        coord, version = cols[0], cols[1]
        if not coord or coord == "Path" or set(coord) <= {"-"}:
            continue
        available[coord] = _normalize_revision(version)
    return available


def _write_github_output(output_file: str, pairs: list[tuple[str, str]]) -> None:
    if not output_file:
        return
    for k, v in pairs:
        if "\n" in k or "\r" in k or "\n" in v or "\r" in v:
            raise ValueError(f"unexpected newline in output {k!r}")
    with open(output_file, "a", encoding="utf-8") as f:
        for k, v in pairs:
            f.write(f"{k}={v}\n")


def _append_summary(summary_file: str, lines: list[str]) -> None:
    if not summary_file:
        return
    with open(summary_file, "a", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def _find_sdkmanager(sdk_root: Path) -> str | None:
    candidates = [
        sdk_root / "cmdline-tools" / "latest" / "bin" / "sdkmanager",
        sdk_root / "cmdline-tools" / "bin" / "sdkmanager",
    ]
    for cand in candidates:
        if cand.is_file() and os.access(cand, os.X_OK):
            return str(cand)
    return shutil.which("sdkmanager")


def _rmtree_force(path: Path) -> None:
    if not path.exists() and not path.is_symlink():
        return
    if path.is_symlink() or path.is_file():
        path.unlink(missing_ok=True)
        return

    def _on_error(func, target, _exc_info):
        try:
            os.chmod(target, 0o700)
            func(target)
        except OSError:
            pass

    shutil.rmtree(path, onerror=_on_error)


def clean_sdk_packages(sdk_root: Path, api_level: str, system_image: str) -> None:
    """Remove only the 4 cached SDK package directories under `sdk_root`."""
    root_resolved = sdk_root.resolve()
    for _tag, _coord, rel in package_specs(api_level, system_image):
        target = sdk_root / rel
        resolved_parent = (
            target.parent.resolve() if target.parent.exists() else root_resolved
        )
        if (
            root_resolved != resolved_parent
            and root_resolved not in resolved_parent.parents
        ):
            raise ValueError(f"refusing to delete path outside sdk_root: {target}")
        _rmtree_force(target)


def verify_sdk(
    sdk_root: Path,
    runner_os: str,
    runner_arch: str,
    api_level: str,
    system_image: str,
    expected_key: str = "",
) -> tuple[bool, str, list[str]]:
    """Verify the 4 installed SDK packages and return `(ok, resolved_key, errors)`."""
    errors: list[str] = []
    if not sdk_root.is_dir():
        return False, "", [f"SDK root does not exist: {sdk_root}"]

    prefix = build_key_prefix(runner_os, runner_arch, api_level, system_image)
    specs = package_specs(api_level, system_image)
    revisions_by_tag: dict[str, str] = {}
    revisions_by_coord: dict[str, str] = {}

    for tag, coord, rel in specs:
        pkg_dir = sdk_root / rel
        if not pkg_dir.is_dir():
            errors.append(f"missing package directory {pkg_dir}")
            continue
        try:
            rev = read_package_xml_revision(pkg_dir / "package.xml", coord)
            revisions_by_tag[tag] = rev
            revisions_by_coord[coord] = rev
        except ValueError as exc:
            errors.append(str(exc))

    # System image payload sanity checks beyond metadata.
    img_dir = sdk_root / specs[3][2]
    if img_dir.is_dir():
        for marker in ("source.properties", "build.prop"):
            if not (img_dir / marker).is_file():
                errors.append(f"system image missing {img_dir / marker}")
        sys_img = img_dir / "system.img"
        if not sys_img.is_file() or sys_img.stat().st_size <= 0:
            errors.append(f"system image missing or empty {sys_img}")

    sdkmanager_bin = _find_sdkmanager(sdk_root)
    if sdkmanager_bin is None:
        errors.append("sdkmanager binary not found")
    else:
        try:
            proc = subprocess.run(
                [sdkmanager_bin, f"--sdk_root={sdk_root}", "--list_installed"],
                capture_output=True,
                text=True,
                timeout=60,
                check=False,
            )
            if proc.returncode != 0:
                errors.append(
                    f"sdkmanager --list_installed exited {proc.returncode}: {proc.stderr.strip()}"
                )
            else:
                listed = parse_sdkmanager_list_installed(proc.stdout)
                for _tag, coord, _rel in specs:
                    if coord not in listed:
                        errors.append(
                            f"sdkmanager --list_installed missing coordinate {coord!r}"
                        )
                    elif (
                        coord in revisions_by_coord
                        and listed[coord] != revisions_by_coord[coord]
                    ):
                        errors.append(
                            f"version mismatch for {coord}: package.xml={revisions_by_coord[coord]!r}, "
                            f"sdkmanager={listed[coord]!r}"
                        )
        except (OSError, subprocess.TimeoutExpired) as exc:
            errors.append(f"failed running sdkmanager --list_installed: {exc}")

    emulator_bin = sdk_root / "emulator" / "emulator"
    if not emulator_bin.is_file() or not os.access(emulator_bin, os.X_OK):
        errors.append(f"missing executable emulator binary at {emulator_bin}")
    else:
        try:
            proc = subprocess.run(
                [str(emulator_bin), "-version"],
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
            combined = f"{proc.stdout}\n{proc.stderr}"
            if proc.returncode != 0:
                errors.append(f"emulator -version exited {proc.returncode}")
            elif "Android emulator version" not in combined:
                errors.append("emulator -version output missing version banner")
        except (OSError, subprocess.TimeoutExpired) as exc:
            errors.append(f"failed running emulator -version: {exc}")

    adb_bin = sdk_root / "platform-tools" / "adb"
    if not adb_bin.is_file() or not os.access(adb_bin, os.X_OK):
        errors.append(f"missing executable adb binary at {adb_bin}")
    else:
        try:
            proc = subprocess.run(
                [str(adb_bin), "version"],
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
            if proc.returncode != 0:
                errors.append(f"adb version exited {proc.returncode}")
        except (OSError, subprocess.TimeoutExpired) as exc:
            errors.append(f"failed running adb version: {exc}")

    if len(revisions_by_tag) == 4:
        resolved_key = build_resolved_key(prefix, revisions_by_tag)
    else:
        resolved_key = ""

    if expected_key and resolved_key and resolved_key != expected_key:
        errors.append(
            f"cache key mismatch: restored {expected_key!r}, resolved {resolved_key!r}"
        )

    return len(errors) == 0, resolved_key, errors


def resolve_target_key(
    sdk_root: Path,
    runner_os: str,
    runner_arch: str,
    api_level: str,
    system_image: str,
) -> tuple[bool, str, list[str]]:
    """Resolve the upstream Android SDK target cache key using `sdkmanager --list` metadata only."""
    if not sdk_root.is_dir():
        return False, "", [f"SDK root does not exist: {sdk_root}"]

    prefix = build_key_prefix(runner_os, runner_arch, api_level, system_image)
    specs = package_specs(api_level, system_image)
    sdkmanager_bin = _find_sdkmanager(sdk_root)
    if sdkmanager_bin is None:
        return False, "", ["sdkmanager binary not found"]

    try:
        proc = subprocess.run(
            [sdkmanager_bin, f"--sdk_root={sdk_root}", "--list"],
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return False, "", [f"failed running sdkmanager --list: {exc}"]

    if proc.returncode != 0:
        return (
            False,
            "",
            [f"sdkmanager --list exited {proc.returncode}: {proc.stderr.strip()}"],
        )

    available = parse_sdkmanager_available_packages(proc.stdout)
    errors: list[str] = []
    revisions_by_tag: dict[str, str] = {}
    for tag, coord, _rel in specs:
        rev = available.get(coord)
        if rev is None:
            errors.append(
                f"sdkmanager --list Available Packages missing coordinate {coord!r}"
            )
            continue
        if not _REVISION_RE.fullmatch(rev):
            errors.append(
                f"invalid upstream revision {rev!r} for {coord!r} in sdkmanager --list"
            )
            continue
        revisions_by_tag[tag] = rev

    if errors:
        return False, "", errors
    return True, build_resolved_key(prefix, revisions_by_tag), []


def _dir_size_bytes(path: Path) -> int:
    total = 0
    if not path.exists():
        return 0
    for root, _dirs, files in os.walk(path, followlinks=False):
        for name in files:
            fp = os.path.join(root, name)
            try:
                total += os.lstat(fp).st_size
            except OSError:
                pass
    return total


def measure_sdk_cache_bytes(
    sdk_root: Path, api_level: str, system_image: str
) -> tuple[int, int, str, list[str]]:
    """Measure uncompressed and compressed (zstd -3 / gzip fallback) archive bytes."""
    rel_paths = [
        p for p in cached_rel_paths(api_level, system_image) if (sdk_root / p).exists()
    ]
    if not rel_paths:
        raise ValueError(f"no SDK cache directories found under {sdk_root}")

    uncompressed = sum(_dir_size_bytes(sdk_root / p) for p in rel_paths)
    zstd_bin = shutil.which("zstd")
    if zstd_bin:
        comp_cmd = [zstd_bin, "-3", "-T0", "-c"]
        comp_name = "zstd"
    else:
        gzip_bin = shutil.which("gzip")
        if not gzip_bin:
            raise RuntimeError("neither zstd nor gzip is installed on PATH")
        comp_cmd = [gzip_bin, "-c"]
        comp_name = "gzip"

    tar_proc = subprocess.Popen(
        ["tar", "-C", str(sdk_root), "-cf", "-", *rel_paths],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    comp_proc = subprocess.Popen(
        comp_cmd,
        stdin=tar_proc.stdout,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert tar_proc.stdout is not None
    tar_proc.stdout.close()

    compressed = 0
    assert comp_proc.stdout is not None
    while True:
        chunk = comp_proc.stdout.read(1024 * 1024)
        if not chunk:
            break
        compressed += len(chunk)

    comp_rc = comp_proc.wait()
    comp_err = (
        comp_proc.stderr.read().decode("utf-8", errors="replace")
        if comp_proc.stderr
        else ""
    )
    tar_rc = tar_proc.wait()
    tar_err = (
        tar_proc.stderr.read().decode("utf-8", errors="replace")
        if tar_proc.stderr
        else ""
    )
    if tar_rc != 0:
        raise RuntimeError(f"tar exited {tar_rc}: {tar_err.strip()}")
    if comp_rc != 0:
        raise RuntimeError(f"{comp_name} exited {comp_rc}: {comp_err.strip()}")

    return uncompressed, compressed, comp_name, rel_paths


def confirm_and_prune_superseded_sdk_caches(
    api,
    *,
    key_prefix: str,
    keep_key: str,
    max_confirm_attempts: int = 5,
    retry_delay_seconds: float = 2.0,
    sleep_fn=time.sleep,
) -> dict:
    """Confirm `keep_key` exists on `refs/heads/main`, then delete superseded `key_prefix*` main caches."""
    if not matches_sdk_key_prefix(keep_key, key_prefix):
        raise ValueError("keep_key must be non-empty and match delimited key_prefix")

    confirmed = False
    last_error = None
    for attempt in range(1, max_confirm_attempts + 1):
        try:
            entries = api.list_caches(key=keep_key)
        except Exception as exc:
            last_error = str(exc)
            entries = []
        if any(
            isinstance(e, dict)
            and e.get("key") == keep_key
            and e.get("ref") == "refs/heads/main"
            for e in entries
        ):
            confirmed = True
            break
        if attempt < max_confirm_attempts and retry_delay_seconds > 0:
            sleep_fn(retry_delay_seconds)

    if not confirmed:
        detail = f" (last error: {last_error})" if last_error else ""
        return {
            "confirmed": False,
            "deleted": [],
            "errors": [],
            "warning": (
                f"New cache key {keep_key!r} on refs/heads/main was not confirmed after "
                f"{max_confirm_attempts} attempt(s){detail}; deleting nothing."
            ),
        }

    try:
        all_entries = api.list_caches()
    except Exception as exc:
        return {
            "confirmed": True,
            "deleted": [],
            "errors": [f"Failed to list caches for pruning: {exc}"],
            "warning": None,
        }

    deleted = []
    errors = []
    for entry in all_entries:
        if not isinstance(entry, dict):
            continue
        if entry.get("ref") != "refs/heads/main":
            continue
        key = entry.get("key")
        if not matches_sdk_key_prefix(key, key_prefix) or key == keep_key:
            continue
        cache_id = entry.get("id")
        if isinstance(cache_id, bool) or not isinstance(cache_id, int):
            errors.append(
                f"Skipping prunable entry {key!r} with invalid id {cache_id!r}"
            )
            continue
        try:
            api.delete_cache(cache_id)
            deleted.append((cache_id, key, entry.get("size_in_bytes")))
        except Exception as exc:
            errors.append(f"Failed to delete cache id={cache_id} key={key!r}: {exc}")

    return {
        "confirmed": True,
        "deleted": deleted,
        "errors": errors,
        "warning": None,
    }


def _env_or_arg(arg_val: str | None, env_name: str) -> str:
    val = arg_val if arg_val is not None else os.environ.get(env_name, "")
    return val.strip()


def _cmd_metadata(args: argparse.Namespace) -> int:
    sdk_root = Path(args.sdk_root)
    if not sdk_root.is_dir():
        print(f"::error::SDK root does not exist: {sdk_root}", file=sys.stderr)
        return 1
    runner_os = _env_or_arg(args.runner_os, "RUNNER_OS")
    runner_arch = _env_or_arg(args.runner_arch, "RUNNER_ARCH")
    api_level = _env_or_arg(args.api_level, "API_LEVEL")
    system_image = _env_or_arg(args.system_image, "SYSTEM_IMAGE")

    prefix = build_key_prefix(runner_os, runner_arch, api_level, system_image)
    specs = package_specs(api_level, system_image)
    outputs = [
        ("sdk-root", str(sdk_root)),
        ("key-prefix", prefix),
        ("lookup-key", f"{prefix}exact"),
        ("platform-tools-path", str(sdk_root / specs[0][2])),
        ("emulator-path", str(sdk_root / specs[1][2])),
        ("platform-path", str(sdk_root / specs[2][2])),
        ("system-image-path", str(sdk_root / specs[3][2])),
        ("licenses-path", str(sdk_root / "licenses")),
    ]
    _write_github_output(args.github_output, outputs)
    return 0


def _cmd_clean(args: argparse.Namespace) -> int:
    sdk_root = Path(args.sdk_root)
    api_level = _env_or_arg(args.api_level, "API_LEVEL")
    system_image = _env_or_arg(args.system_image, "SYSTEM_IMAGE")
    clean_sdk_packages(sdk_root, api_level, system_image)
    return 0


def _cmd_resolve_target(args: argparse.Namespace) -> int:
    sdk_root = Path(args.sdk_root)
    runner_os = _env_or_arg(args.runner_os, "RUNNER_OS")
    runner_arch = _env_or_arg(args.runner_arch, "RUNNER_ARCH")
    api_level = _env_or_arg(args.api_level, "API_LEVEL")
    system_image = _env_or_arg(args.system_image, "SYSTEM_IMAGE")

    ok, target_key, errors = resolve_target_key(
        sdk_root=sdk_root,
        runner_os=runner_os,
        runner_arch=runner_arch,
        api_level=api_level,
        system_image=system_image,
    )
    if ok:
        print(f"Resolved upstream Android SDK target key: key={target_key}")
        _write_github_output(args.github_output, [("target-key", target_key)])
        return 0

    joined = "; ".join(errors)
    print(
        f"::error::Failed to resolve upstream Android SDK target key: {joined}",
        file=sys.stderr,
        flush=True,
    )
    _write_github_output(args.github_output, [("target-key", "")])
    return 1


def _cmd_verify(args: argparse.Namespace) -> int:
    sdk_root = Path(args.sdk_root)
    runner_os = _env_or_arg(args.runner_os, "RUNNER_OS")
    runner_arch = _env_or_arg(args.runner_arch, "RUNNER_ARCH")
    api_level = _env_or_arg(args.api_level, "API_LEVEL")
    system_image = _env_or_arg(args.system_image, "SYSTEM_IMAGE")

    if args.cache_hit is not None and args.cache_hit != "true":
        ok = False
        resolved_key = ""
        errors = [f"cache restore was not an exact hit (cache-hit={args.cache_hit!r})"]
    else:
        ok, resolved_key, errors = verify_sdk(
            sdk_root=sdk_root,
            runner_os=runner_os,
            runner_arch=runner_arch,
            api_level=api_level,
            system_image=system_image,
            expected_key=args.expected_key,
        )
    if ok:
        print(f"Verified Android SDK packages: key={resolved_key}")
        _write_github_output(
            args.github_output,
            [("usable", "true"), ("resolved-key", resolved_key)],
        )
        return 0

    joined = "; ".join(errors)
    if args.delete_on_failure:
        print(
            f"::warning::Cached Android SDK verification failed ({joined}); deleting cached packages for fresh install",
            flush=True,
        )
        clean_sdk_packages(sdk_root, api_level, system_image)
        _write_github_output(
            args.github_output,
            [("usable", "false"), ("resolved-key", "")],
        )
        return 0

    print(
        f"::error::Android SDK verification failed: {joined}",
        file=sys.stderr,
        flush=True,
    )
    _write_github_output(
        args.github_output,
        [("usable", "false"), ("resolved-key", "")],
    )
    return 1


def _cmd_measure(args: argparse.Namespace) -> int:
    sdk_root = Path(args.sdk_root)
    api_level = _env_or_arg(args.api_level, "API_LEVEL")
    system_image = _env_or_arg(args.system_image, "SYSTEM_IMAGE")
    uncompressed, compressed, comp_name, rel_paths = measure_sdk_cache_bytes(
        sdk_root, api_level, system_image
    )
    comp_mib = compressed / (1024 * 1024)
    uncomp_mib = uncompressed / (1024 * 1024)
    print(
        f"Measured Android SDK cache ({comp_name}): compressed={compressed} B ({comp_mib:.1f} MiB), "
        f"uncompressed={uncompressed} B ({uncomp_mib:.1f} MiB), paths={rel_paths}"
    )
    _write_github_output(
        args.github_output,
        [
            ("compressed-bytes", str(compressed)),
            ("uncompressed-bytes", str(uncompressed)),
            ("compression", comp_name),
        ],
    )
    if args.summary_file:
        _append_summary(
            args.summary_file,
            [
                "### Android Emulator SDK Cache",
                "",
                "| Metric | Value |",
                "|---|---|",
                f"| Cache key | `{args.resolved_key or '(pending)'}` |",
                f"| Compressed size ({comp_name}) | {compressed} B ({comp_mib:.1f} MiB / {compressed / 1_000_000_000:.2f} GB) |",
                f"| Uncompressed size | {uncompressed} B ({uncomp_mib:.1f} MiB) |",
            ],
        )
    return 0


def _cmd_prune(args: argparse.Namespace, sleep_fn=time.sleep) -> int:
    ref = os.environ.get("GITHUB_REF", "")
    if ref != "refs/heads/main":
        print(
            f"::warning::Refusing to prune Android SDK caches on non-main ref ({ref!r}); deleting nothing.",
            flush=True,
        )
        return 0
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    token = os.environ.get("GH_TOKEN", "")
    api_url = os.environ.get("GITHUB_API_URL", "https://api.github.com")
    if not repo or "/" not in repo or not token:
        print(
            "::warning::Missing GITHUB_REPOSITORY or GH_TOKEN; skipping Android SDK cache prune.",
            flush=True,
        )
        return 0

    guard_dir = Path(__file__).resolve().parent.parent / "setup-bazel"
    if str(guard_dir) not in sys.path:
        sys.path.insert(0, str(guard_dir))
    from cache_capacity_guard import GitHubCacheApi  # type: ignore

    api = GitHubCacheApi(api_url, repo, token)
    res = confirm_and_prune_superseded_sdk_caches(
        api,
        key_prefix=args.key_prefix,
        keep_key=args.keep_key,
        sleep_fn=sleep_fn,
    )
    if not res["confirmed"]:
        print(f"::warning::{res['warning']}", flush=True)
        _append_summary(args.summary_file, [res["warning"]])
        return 0
    for err in res["errors"]:
        print(f"::warning::{err}", flush=True)
    if res["deleted"]:
        items = ", ".join(f"{k} (id={cid})" for cid, k, _s in res["deleted"])
        msg = f"Confirmed {args.keep_key}; pruned {len(res['deleted'])} superseded Android SDK cache(s): {items}."
    else:
        msg = f"Confirmed {args.keep_key}; no superseded Android SDK caches to prune."
    print(msg, flush=True)
    _append_summary(args.summary_file, [msg])
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    def add_sdk_flags(p: argparse.ArgumentParser, with_os_arch: bool = False) -> None:
        p.add_argument("--sdk-root", required=True)
        p.add_argument("--api-level", default=None)
        p.add_argument("--system-image", default=None)
        if with_os_arch:
            p.add_argument("--runner-os", default=None)
            p.add_argument("--runner-arch", default=None)

    p_meta = sub.add_parser("metadata")
    add_sdk_flags(p_meta, with_os_arch=True)
    p_meta.add_argument("--github-output", default=os.environ.get("GITHUB_OUTPUT", ""))

    p_resolve = sub.add_parser("resolve-target")
    add_sdk_flags(p_resolve, with_os_arch=True)
    p_resolve.add_argument(
        "--github-output", default=os.environ.get("GITHUB_OUTPUT", "")
    )

    p_clean = sub.add_parser("clean")
    add_sdk_flags(p_clean, with_os_arch=False)

    p_verify = sub.add_parser("verify")
    add_sdk_flags(p_verify, with_os_arch=True)
    p_verify.add_argument("--expected-key", default="")
    p_verify.add_argument("--cache-hit", default=None)
    p_verify.add_argument("--delete-on-failure", action="store_true")
    p_verify.add_argument(
        "--github-output", default=os.environ.get("GITHUB_OUTPUT", "")
    )

    p_measure = sub.add_parser("measure")
    add_sdk_flags(p_measure, with_os_arch=False)
    p_measure.add_argument("--resolved-key", default="")
    p_measure.add_argument(
        "--github-output", default=os.environ.get("GITHUB_OUTPUT", "")
    )
    p_measure.add_argument(
        "--summary-file", default=os.environ.get("GITHUB_STEP_SUMMARY", "")
    )

    p_prune = sub.add_parser("prune")
    p_prune.add_argument("--key-prefix", required=True)
    p_prune.add_argument("--keep-key", required=True)
    p_prune.add_argument(
        "--summary-file", default=os.environ.get("GITHUB_STEP_SUMMARY", "")
    )

    args = parser.parse_args(argv)
    if args.cmd == "metadata":
        return _cmd_metadata(args)
    if args.cmd == "resolve-target":
        return _cmd_resolve_target(args)
    if args.cmd == "clean":
        return _cmd_clean(args)
    if args.cmd == "verify":
        return _cmd_verify(args)
    if args.cmd == "measure":
        return _cmd_measure(args)
    if args.cmd == "prune":
        return _cmd_prune(args)
    return 2


if __name__ == "__main__":
    sys.exit(main())
