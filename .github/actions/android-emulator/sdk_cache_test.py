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

"""Tests for .github/actions/android-emulator/sdk_cache.py, action.yml, and android-emulator-cache.yaml."""

from __future__ import annotations

import http.server
import json
import os
import re
import sys
import threading
from pathlib import Path

import pytest
import yaml

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import sdk_cache


def _write_pkg_xml(
    path: Path,
    coord: str,
    major: str,
    minor: str = "",
    micro: str = "",
    preview: str = "",
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    rev_parts = [f"<major>{major}</major>"]
    if minor:
        rev_parts.append(f"<minor>{minor}</minor>")
    if micro:
        rev_parts.append(f"<micro>{micro}</micro>")
    if preview:
        rev_parts.append(f"<preview>{preview}</preview>")
    xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<ns2:repository xmlns:ns2="http://schemas.android.com/repository/android/common/02">\n'
        f'  <localPackage path="{coord}" obsolete="false">\n'
        f"    <revision>{''.join(rev_parts)}</revision>\n"
        "  </localPackage>\n"
        "</ns2:repository>\n"
    )
    path.write_text(xml, encoding="utf-8")


def _make_fake_sdk(
    tmp_path: Path, *, list_output: str | None = None, emu_rc: int = 0
) -> Path:
    sdk = tmp_path / "android-sdk"
    api = "35"
    sys_img = "system-images;android-35;google_atd;x86_64"
    sys_rel = "system-images/android-35/google_atd/x86_64"

    _write_pkg_xml(
        sdk / "platform-tools" / "package.xml", "platform-tools", "37", "0", "1"
    )
    _write_pkg_xml(sdk / "emulator" / "package.xml", "emulator", "37", "1", "11")
    _write_pkg_xml(
        sdk / f"platforms/android-{api}/package.xml", f"platforms;android-{api}", "2"
    )
    _write_pkg_xml(sdk / sys_rel / "package.xml", sys_img, "9")

    (sdk / sys_rel / "source.properties").write_text(
        "Pkg.Revision=9\n", encoding="utf-8"
    )
    (sdk / sys_rel / "build.prop").write_text(
        "ro.build.version.sdk=35\n", encoding="utf-8"
    )
    (sdk / sys_rel / "system.img").write_bytes(b"fake-system-image-payload")
    (sdk / "licenses").mkdir(parents=True, exist_ok=True)
    (sdk / "licenses" / "android-sdk-license").write_text(
        "accepted\n", encoding="utf-8"
    )

    # Sentinel inside cmdline-tools that clean/delete-on-failure must never delete.
    cmdline_bin = sdk / "cmdline-tools" / "latest" / "bin"
    cmdline_bin.mkdir(parents=True, exist_ok=True)
    (sdk / "cmdline-tools" / "latest" / "KEEP_ME").write_text(
        "keep\n", encoding="utf-8"
    )

    if list_output is None:
        list_output = (
            "WARNING: The SDK Manager CLI tool (sdkmanager) is deprecated.\n"
            "Installed packages:\n"
            "  Path                                            | Version | Description | Location\n"
            "  -------                                         | ------- | -------     | -------\n"
            "  platform-tools                                  | 37.0.1  | PT          | platform-tools\n"
            "  emulator                                        | 37.1.11 | Emu         | emulator\n"
            "  platforms;android-35                            | 2       | Plat        | platforms/android-35\n"
            "  system-images;android-35;google_atd;x86_64      | 9       | SysImg      | system-images/android-35/google_atd/x86_64\n"
        )
    sdkmgr = cmdline_bin / "sdkmanager"
    sdkmgr.write_text(
        f"#!/usr/bin/env bash\ncat <<'EOF'\n{list_output}EOF\n",
        encoding="utf-8",
    )
    sdkmgr.chmod(0o755)

    emu = sdk / "emulator" / "emulator"
    emu.write_text(
        "#!/usr/bin/env bash\n"
        f"echo 'Android emulator version 37.1.11.0 (build_id 123)'\n"
        f"exit {emu_rc}\n",
        encoding="utf-8",
    )
    emu.chmod(0o755)

    adb = sdk / "platform-tools" / "adb"
    adb.write_text(
        "#!/usr/bin/env bash\necho 'Android Debug Bridge version 1.0.41'\nexit 0\n",
        encoding="utf-8",
    )
    adb.chmod(0o755)
    return sdk


def test_validation_and_key_formatting():
    assert sdk_cache.validate_api_level("35") == "35"
    assert sdk_cache.validate_api_level("37.0") == "37.0"
    with pytest.raises(ValueError):
        sdk_cache.validate_api_level("35;rm -rf /")

    img = "system-images;android-35;google_atd;x86_64"
    assert sdk_cache.validate_system_image(img) == img
    for bad in (
        "system-images;..;google_atd;x86_64",
        "platform-tools",
        "system-images;a;b;c;d",
    ):
        with pytest.raises(ValueError):
            sdk_cache.validate_system_image(bad)

    prefix = sdk_cache.build_key_prefix("Linux", "X64", "35", img)
    assert "-v1-" in prefix
    assert (
        prefix
        == "android-emulator-sdk-v1-Linux-X64-api35-system-images_android-35_google_atd_x86_64-rev-"
    )
    key = sdk_cache.build_resolved_key(
        prefix, {"pt": "37.0.1", "emu": "37.1.11", "plat": "2", "img": "9"}
    )
    assert key == f"{prefix}pt37.0.1-emu37.1.11-plat2-img9"


def test_matches_sdk_key_prefix_delimited():
    arm64_prefix = sdk_cache.build_key_prefix(
        "Linux", "ARM64", "35", "system-images;android-35;google_apis;arm64"
    )
    arm64_v8a_prefix = sdk_cache.build_key_prefix(
        "Linux", "ARM64", "35", "system-images;android-35;google_apis;arm64-v8a"
    )
    arm64_key = sdk_cache.build_resolved_key(
        arm64_prefix, {"pt": "37.0.1", "emu": "37.1.11", "plat": "2", "img": "9"}
    )
    arm64_v8a_key = sdk_cache.build_resolved_key(
        arm64_v8a_prefix, {"pt": "37.0.1", "emu": "37.1.11", "plat": "2", "img": "9"}
    )

    assert sdk_cache.matches_sdk_key_prefix(arm64_key, arm64_prefix)
    assert sdk_cache.matches_sdk_key_prefix(arm64_key, arm64_prefix.rstrip("-"))
    assert not sdk_cache.matches_sdk_key_prefix(arm64_v8a_key, arm64_prefix)
    assert not sdk_cache.matches_sdk_key_prefix(arm64_v8a_key, arm64_prefix.rstrip("-"))

    # Undelimited prefixes cannot bleed across coordinate suffixes or extra segments.
    x86_undelimited = "android-emulator-sdk-v1-Linux-X64-api35-system-images_android-35_google_apis_x86"
    x86_64_key = "android-emulator-sdk-v1-Linux-X64-api35-system-images_android-35_google_apis_x86_64-rev-pt37.0.1-emu37.1.11-plat2-img9"
    assert not sdk_cache.matches_sdk_key_prefix(x86_64_key, x86_undelimited)

    apis_prefix = sdk_cache.build_key_prefix(
        "Linux", "X64", "35", "system-images;android-35;google_apis;x86_64"
    )
    playstore_key = sdk_cache.build_resolved_key(
        sdk_cache.build_key_prefix(
            "Linux",
            "X64",
            "35",
            "system-images;android-35;google_apis_playstore;x86_64",
        ),
        {"pt": "37.0.1", "emu": "37.1.11", "plat": "2", "img": "9"},
    )
    assert not sdk_cache.matches_sdk_key_prefix(playstore_key, apis_prefix)
    assert not sdk_cache.matches_sdk_key_prefix(f"{apis_prefix}exact", apis_prefix)


def test_package_xml_and_list_installed_parsing(tmp_path):
    xml_path = tmp_path / "package.xml"
    _write_pkg_xml(xml_path, "emulator", "37", "1", "11", "2")
    assert sdk_cache.read_package_xml_revision(xml_path, "emulator") == "37.1.11-rc2"

    with pytest.raises(ValueError):
        sdk_cache.read_package_xml_revision(xml_path, "platform-tools")

    corrupt = tmp_path / "bad.xml"
    corrupt.write_text("<not-xml", encoding="utf-8")
    with pytest.raises(ValueError):
        sdk_cache.read_package_xml_revision(corrupt, "emulator")

    parsed = sdk_cache.parse_sdkmanager_list_installed(
        "WARNING: deprecated\n"
        "Installed packages:\n"
        "  Path | Version | Description | Location\n"
        "  ---  | ---     | ---         | ---\n"
        "  platform-tools | 37.0.1 | PT | platform-tools\n"
        "  platforms;android-35 | 2 | P | platforms/android-35\n"
    )
    assert parsed == {"platform-tools": "37.0.1", "platforms;android-35": "2"}


def test_verify_succeeds_and_catches_corruption(tmp_path):
    sdk = _make_fake_sdk(tmp_path)
    out_file = tmp_path / "out.txt"
    expected = (
        "android-emulator-sdk-v1-Linux-X64-api35-"
        "system-images_android-35_google_atd_x86_64-rev-pt37.0.1-emu37.1.11-plat2-img9"
    )
    rc = sdk_cache.main(
        [
            "verify",
            "--sdk-root",
            str(sdk),
            "--runner-os",
            "Linux",
            "--runner-arch",
            "X64",
            "--api-level",
            "35",
            "--system-image",
            "system-images;android-35;google_atd;x86_64",
            "--expected-key",
            expected,
            "--github-output",
            str(out_file),
        ]
    )
    assert rc == 0
    text = out_file.read_text(encoding="utf-8")
    assert "usable=true" in text
    assert f"resolved-key={expected}" in text

    # Strict verify fails (exit 1) on expected-key mismatch without deleting.
    rc_bad_key = sdk_cache.main(
        [
            "verify",
            "--sdk-root",
            str(sdk),
            "--runner-os",
            "Linux",
            "--runner-arch",
            "X64",
            "--api-level",
            "35",
            "--system-image",
            "system-images;android-35;google_atd;x86_64",
            "--expected-key",
            "wrong-key",
        ]
    )
    assert rc_bad_key == 1
    assert (sdk / "emulator" / "emulator").exists()

    # Empty system.img triggers --delete-on-failure cleanup of the 4 package dirs while keeping cmdline-tools.
    (sdk / "system-images/android-35/google_atd/x86_64/system.img").write_bytes(b"")
    out_fail = tmp_path / "out_fail.txt"
    rc_del = sdk_cache.main(
        [
            "verify",
            "--sdk-root",
            str(sdk),
            "--runner-os",
            "Linux",
            "--runner-arch",
            "X64",
            "--api-level",
            "35",
            "--system-image",
            "system-images;android-35;google_atd;x86_64",
            "--delete-on-failure",
            "--github-output",
            str(out_fail),
        ]
    )
    assert rc_del == 0
    assert "usable=false" in out_fail.read_text(encoding="utf-8")
    assert not (sdk / "platform-tools").exists()
    assert not (sdk / "emulator").exists()
    assert not (sdk / "platforms/android-35").exists()
    assert not (sdk / "system-images/android-35/google_atd/x86_64").exists()
    assert (sdk / "cmdline-tools/latest/KEEP_ME").is_file()


def test_verify_fails_when_emulator_or_list_installed_broken(tmp_path):
    sdk_emu = _make_fake_sdk(tmp_path / "emu_fail", emu_rc=1)
    rc_emu = sdk_cache.main(
        [
            "verify",
            "--sdk-root",
            str(sdk_emu),
            "--runner-os",
            "Linux",
            "--runner-arch",
            "X64",
            "--api-level",
            "35",
            "--system-image",
            "system-images;android-35;google_atd;x86_64",
        ]
    )
    assert rc_emu == 1

    sdk_list = _make_fake_sdk(
        tmp_path / "list_fail",
        list_output=(
            "Installed packages:\n"
            "  Path | Version | Description | Location\n"
            "  ---  | ---     | ---         | ---\n"
            "  platform-tools | 37.0.1 | PT | platform-tools\n"
        ),
    )
    rc_list = sdk_cache.main(
        [
            "verify",
            "--sdk-root",
            str(sdk_list),
            "--runner-os",
            "Linux",
            "--runner-arch",
            "X64",
            "--api-level",
            "35",
            "--system-image",
            "system-images;android-35;google_atd;x86_64",
        ]
    )
    assert rc_list == 1


def test_measure_outputs_sizes(tmp_path):
    sdk = _make_fake_sdk(tmp_path)
    out = tmp_path / "measure_out.txt"
    summary = tmp_path / "measure_sum.md"
    rc = sdk_cache.main(
        [
            "measure",
            "--sdk-root",
            str(sdk),
            "--api-level",
            "35",
            "--system-image",
            "system-images;android-35;google_atd;x86_64",
            "--resolved-key",
            "k1",
            "--github-output",
            str(out),
            "--summary-file",
            str(summary),
        ]
    )
    assert rc == 0
    out_text = out.read_text(encoding="utf-8")
    assert "compressed-bytes=" in out_text
    assert "uncompressed-bytes=" in out_text
    assert "k1" in summary.read_text(encoding="utf-8")


def test_resolve_target_key_from_sdkmanager_list(tmp_path):
    sdk = _make_fake_sdk(tmp_path / "ok")
    sdkmgr = sdk / "cmdline-tools" / "latest" / "bin" / "sdkmanager"
    sdkmgr.write_text(
        "#!/usr/bin/env bash\n"
        'if [[ "$*" == *"--list_installed"* ]]; then\n'
        "  echo 'Installed packages:'\n"
        "  exit 0\n"
        "fi\n"
        "cat <<'EOF'\n"
        "Installed packages:\n"
        "  Path | Version | Description | Location\n"
        "  ---  | ---     | ---         | ---\n"
        "  platform-tools | 36.0.0 | PT | platform-tools\n"
        "Available Packages:\n"
        "  Path | Version | Description\n"
        "  ---  | ---     | ---\n"
        "  platform-tools | 37.0.3 | Platform Tools\n"
        "  emulator | 37.3.10 rc2 | Android Emulator\n"
        "  platforms;android-35 | 2 | Android SDK Platform 35\n"
        "  system-images;android-35;google_atd;x86_64 | 1 | ATD Image\n"
        "Available Updates:\n"
        "  platform-tools | 37.0.0 | 37.0.3\n"
        "EOF\n",
        encoding="utf-8",
    )
    sdkmgr.chmod(0o755)
    out_file = tmp_path / "resolve_out.txt"
    rc = sdk_cache.main(
        [
            "resolve-target",
            "--sdk-root",
            str(sdk),
            "--runner-os",
            "Linux",
            "--runner-arch",
            "X64",
            "--api-level",
            "35",
            "--system-image",
            "system-images;android-35;google_atd;x86_64",
            "--github-output",
            str(out_file),
        ]
    )
    assert rc == 0
    expected = (
        "android-emulator-sdk-v1-Linux-X64-api35-"
        "system-images_android-35_google_atd_x86_64-rev-"
        "pt37.0.3-emu37.3.10-rc2-plat2-img1"
    )
    assert f"target-key={expected}" in out_file.read_text(encoding="utf-8")

    # Missing coordinate in Available Packages fails cleanly.
    sdk_missing = _make_fake_sdk(tmp_path / "missing")
    sdkmgr_missing = sdk_missing / "cmdline-tools" / "latest" / "bin" / "sdkmanager"
    sdkmgr_missing.write_text(
        "#!/usr/bin/env bash\n"
        "cat <<'EOF'\n"
        "Available Packages:\n"
        "  Path | Version | Description\n"
        "  ---  | ---     | ---\n"
        "  platform-tools | 37.0.3 | PT\n"
        "EOF\n",
        encoding="utf-8",
    )
    sdkmgr_missing.chmod(0o755)
    out_missing = tmp_path / "resolve_missing.txt"
    rc_missing = sdk_cache.main(
        [
            "resolve-target",
            "--sdk-root",
            str(sdk_missing),
            "--runner-os",
            "Linux",
            "--runner-arch",
            "X64",
            "--api-level",
            "35",
            "--system-image",
            "system-images;android-35;google_atd;x86_64",
            "--github-output",
            str(out_missing),
        ]
    )
    assert rc_missing == 1
    assert "target-key=\n" in out_missing.read_text(encoding="utf-8")

    # Non-zero sdkmanager --list fails cleanly.
    sdk_fail = _make_fake_sdk(tmp_path / "fail")
    sdkmgr_fail = sdk_fail / "cmdline-tools" / "latest" / "bin" / "sdkmanager"
    sdkmgr_fail.write_text("#!/usr/bin/env bash\nexit 2\n", encoding="utf-8")
    sdkmgr_fail.chmod(0o755)
    rc_fail = sdk_cache.main(
        [
            "resolve-target",
            "--sdk-root",
            str(sdk_fail),
            "--runner-os",
            "Linux",
            "--runner-arch",
            "X64",
            "--api-level",
            "35",
            "--system-image",
            "system-images;android-35;google_atd;x86_64",
        ]
    )
    assert rc_fail == 1


@pytest.mark.parametrize("cache_hit_arg", ["false", ""])
def test_partial_restore_non_exact_hit_deletes_restored_dirs(tmp_path, cache_hit_arg):
    sdk = _make_fake_sdk(tmp_path / f"partial_{cache_hit_arg or 'empty'}")
    out_file = tmp_path / f"out_{cache_hit_arg or 'empty'}.txt"
    expected = (
        "android-emulator-sdk-v1-Linux-X64-api35-"
        "system-images_android-35_google_atd_x86_64-rev-pt37.0.1-emu37.1.11-plat2-img9"
    )
    rc = sdk_cache.main(
        [
            "verify",
            "--sdk-root",
            str(sdk),
            "--runner-os",
            "Linux",
            "--runner-arch",
            "X64",
            "--api-level",
            "35",
            "--system-image",
            "system-images;android-35;google_atd;x86_64",
            "--expected-key",
            expected,
            "--cache-hit",
            cache_hit_arg,
            "--delete-on-failure",
            "--github-output",
            str(out_file),
        ]
    )
    assert rc == 0
    assert "usable=false" in out_file.read_text(encoding="utf-8")
    assert not (sdk / "platform-tools").exists()
    assert not (sdk / "emulator").exists()
    assert not (sdk / "platforms/android-35").exists()
    assert not (sdk / "system-images/android-35/google_atd/x86_64").exists()
    assert (sdk / "cmdline-tools/latest/KEEP_ME").is_file()


def test_partial_restore_missing_dir_deletes_remaining_dirs(tmp_path):
    sdk = _make_fake_sdk(tmp_path / "missing_dir")
    (sdk / "system-images/android-35/google_atd/x86_64/system.img").unlink()
    (sdk / "system-images/android-35/google_atd/x86_64/build.prop").unlink()
    (sdk / "system-images/android-35/google_atd/x86_64/source.properties").unlink()
    (sdk / "system-images/android-35/google_atd/x86_64/package.xml").unlink()
    (sdk / "system-images/android-35/google_atd/x86_64").rmdir()
    out_file = tmp_path / "out_missing.txt"
    rc = sdk_cache.main(
        [
            "verify",
            "--sdk-root",
            str(sdk),
            "--runner-os",
            "Linux",
            "--runner-arch",
            "X64",
            "--api-level",
            "35",
            "--system-image",
            "system-images;android-35;google_atd;x86_64",
            "--cache-hit",
            "true",
            "--delete-on-failure",
            "--github-output",
            str(out_file),
        ]
    )
    assert rc == 0
    assert "usable=false" in out_file.read_text(encoding="utf-8")
    assert not (sdk / "platform-tools").exists()
    assert not (sdk / "emulator").exists()
    assert not (sdk / "platforms/android-35").exists()
    assert (sdk / "cmdline-tools/latest/KEEP_ME").is_file()


def test_prune_superseded_main_only(monkeypatch):
    prefix = "android-emulator-sdk-v1-Linux-ARM64-api35-system-images_android-35_google_apis_arm64-rev-"
    keep_key = f"{prefix}pt37.0.1-emu37.1.11-plat2-img9"
    old_key = f"{prefix}pt36.0.0-emu36.1.0-plat1-img8"
    pr_key = f"{prefix}pt35.0.0-emu35.1.0-plat1-img7"
    sibling_coord_key = (
        "android-emulator-sdk-v1-Linux-ARM64-api35-"
        "system-images_android-35_google_apis_arm64-v8a-rev-pt36.0.0-emu36.1.0-plat1-img8"
    )
    deleted: list[int] = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def _send(self, code, body):
            self.send_response(code)
            if body is not None:
                self.send_header("Content-Type", "application/json")
            self.end_headers()
            if body is not None:
                self.wfile.write(json.dumps(body).encode("utf-8"))

        def do_GET(self):
            entries = [
                {
                    "id": 1,
                    "ref": "refs/heads/main",
                    "key": keep_key,
                    "size_in_bytes": 100,
                },
                {
                    "id": 2,
                    "ref": "refs/heads/main",
                    "key": old_key,
                    "size_in_bytes": 100,
                },
                {
                    "id": 3,
                    "ref": "refs/pull/12/merge",
                    "key": pr_key,
                    "size_in_bytes": 100,
                },
                {
                    "id": 4,
                    "ref": "refs/heads/main",
                    "key": sibling_coord_key,
                    "size_in_bytes": 100,
                },
            ]
            self._send(200, {"actions_caches": entries, "total_count": len(entries)})

        def do_DELETE(self):
            deleted.append(int(self.path.rsplit("/", 1)[-1]))
            self._send(204, None)

        def log_message(self, _fmt, *_args):
            pass

    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    th = threading.Thread(target=srv.serve_forever, daemon=True)
    th.start()
    try:
        api_url = f"http://127.0.0.1:{srv.server_address[1]}"
        monkeypatch.setenv("GITHUB_REF", "refs/heads/main")
        monkeypatch.setenv("GITHUB_REPOSITORY", "o/r")
        monkeypatch.setenv("GH_TOKEN", "tok")
        monkeypatch.setenv("GITHUB_API_URL", api_url)
        rc = sdk_cache.main(["prune", "--key-prefix", prefix, "--keep-key", keep_key])
        assert rc == 0
        assert deleted == [2]

        deleted.clear()
        monkeypatch.setenv("GITHUB_REF", "refs/pull/42/merge")
        rc_pr = sdk_cache.main(
            ["prune", "--key-prefix", prefix, "--keep-key", keep_key]
        )
        assert rc_pr == 0
        assert deleted == []
    finally:
        srv.shutdown()
        srv.server_close()


def _eval_action_if(expr: str, ctx: dict) -> bool:
    s = expr.strip()
    if s.startswith("${{") and s.endswith("}}"):
        s = s[3:-2].strip()

    def repl_input(m: re.Match[str]) -> str:
        return repr(ctx["inputs"].get(m.group(1), ""))

    def repl_output(m: re.Match[str]) -> str:
        step_id, out_name = m.group(1), m.group(2)
        return repr(ctx["outputs"].get(step_id, {}).get(out_name, ""))

    def repl_outcome(m: re.Match[str]) -> str:
        return repr(ctx["outcomes"].get(m.group(1), "skipped"))

    s = s.replace("github.ref", repr(ctx["github_ref"]))
    s = re.sub(r"inputs\.([A-Za-z0-9_-]+)", repl_input, s)
    s = re.sub(r"steps\.([A-Za-z0-9_-]+)\.outputs\.([A-Za-z0-9_-]+)", repl_output, s)
    s = re.sub(r"steps\.([A-Za-z0-9_-]+)\.outcome", repl_outcome, s)
    s = s.replace("failure()", repr(ctx.get("failed", False)))
    s = s.replace("&&", " and ").replace("||", " or ")
    return bool(eval(s, {"__builtins__": {}}, {}))


def _simulate_action_steps(
    *,
    github_ref: str,
    boot: str,
    github_token: str,
    cache_limit_gb: str,
    warm_hit: str = "false",
    target_key: str = "android-emulator-sdk-v1-Linux-X64-api35-system-images_android-35_google_atd_x86_64-rev-pt37.0.3-emu37.3.10-plat2-img1",
    prefix_matched_key: str = "",
    restore_hit: str = "false",
    verify_usable: str = "false",
    resolved_key: str = "android-emulator-sdk-v1-Linux-X64-api35-system-images_android-35_google_atd_x86_64-rev-pt37.0.3-emu37.3.10-plat2-img1",
    exact_hit: str = "false",
    allow_save: str = "true",
) -> list[str]:
    action_path = Path(os.environ["ANDROID_EMULATOR_ACTION_PATH"])
    action = yaml.safe_load(action_path.read_text(encoding="utf-8"))
    ctx = {
        "github_ref": github_ref,
        "inputs": {
            "boot": boot,
            "github-token": github_token,
            "cache-limit-gb": cache_limit_gb,
        },
        "outputs": {
            "sdk": {"sdk-root": "/opt/android-sdk", "key-prefix": "prefix-"},
            "warm-target": {"target-key": ""},
            "warm-lookup": {"cache-hit": ""},
            "cache-lookup": {"cache-matched-key": ""},
            "cache-restore": {"cache-hit": ""},
            "verify-restore": {"usable": "", "resolved-key": ""},
            "resolved": {"resolved-key": ""},
            "exact-lookup": {"cache-hit": ""},
            "measure": {"compressed-bytes": ""},
            "capacity-guard": {"allow_save": ""},
        },
        "outcomes": {},
        "failed": False,
    }
    executed: list[str] = []
    for step in action["runs"]["steps"]:
        sid = step.get("id") or step["name"]
        cond = step.get("if")
        if cond is not None and not _eval_action_if(str(cond), ctx):
            ctx["outcomes"][sid] = "skipped"
            continue
        executed.append(sid)
        ctx["outcomes"][sid] = "success"
        if sid == "warm-target":
            ctx["outputs"]["warm-target"]["target-key"] = target_key
        elif sid == "warm-lookup":
            ctx["outputs"]["warm-lookup"]["cache-hit"] = warm_hit
        elif sid == "cache-lookup":
            ctx["outputs"]["cache-lookup"]["cache-matched-key"] = prefix_matched_key
        elif sid == "cache-restore":
            ctx["outputs"]["cache-restore"]["cache-hit"] = restore_hit
        elif sid == "verify-restore":
            ctx["outputs"]["verify-restore"]["usable"] = verify_usable
            ctx["outputs"]["verify-restore"]["resolved-key"] = (
                resolved_key if verify_usable == "true" else ""
            )
        elif sid == "resolved":
            ctx["outputs"]["resolved"]["resolved-key"] = resolved_key
        elif sid == "exact-lookup":
            ctx["outputs"]["exact-lookup"]["cache-hit"] = exact_hit
        elif sid == "measure":
            ctx["outputs"]["measure"]["compressed-bytes"] = "1240000000"
        elif sid == "capacity-guard":
            ctx["outputs"]["capacity-guard"]["allow_save"] = allow_save
    return executed


def test_action_warm_and_presubmit_paths():
    # 1. Main warm with unchanged upstream revision: metadata lookup hits, zero restore/install/save work.
    hit_steps = _simulate_action_steps(
        github_ref="refs/heads/main",
        boot="false",
        github_token="tok",
        cache_limit_gb="20",
        warm_hit="true",
    )
    assert hit_steps == ["sdk", "warm-target", "warm-lookup"]

    # 2. Main warm with newer upstream revision: metadata lookup misses -> installs, verifies, measures, guards, saves, prunes (no 2 GB restore).
    miss_steps = _simulate_action_steps(
        github_ref="refs/heads/main",
        boot="false",
        github_token="tok",
        cache_limit_gb="20",
        warm_hit="false",
    )
    assert "warm-lookup" in miss_steps
    assert "cache-lookup" not in miss_steps
    assert "cache-restore" not in miss_steps
    for expected_step in (
        "Install the emulator and system image",
        "resolved",
        "measure",
        "capacity-guard",
        "cache-save",
        "Prune superseded Android SDK caches (main only)",
    ):
        assert expected_step in miss_steps

    # 3. Presubmit (PR / merge queue): prefix restore + verify only; never runs warm or save-only work.
    pr_steps = _simulate_action_steps(
        github_ref="refs/pull/5556/merge",
        boot="true",
        github_token="",
        cache_limit_gb="",
        prefix_matched_key="prefix-old",
        restore_hit="true",
        verify_usable="true",
    )
    assert "cache-lookup" in pr_steps
    assert "cache-restore" in pr_steps
    assert "verify-restore" in pr_steps
    for forbidden_step in (
        "warm-target",
        "warm-lookup",
        "exact-lookup",
        "measure",
        "capacity-guard",
        "cache-save",
        "Prune superseded Android SDK caches (main only)",
    ):
        assert forbidden_step not in pr_steps

    # 4. Main run without token or cache-limit-gb never runs measure/guard/save/prune.
    no_token_steps = _simulate_action_steps(
        github_ref="refs/heads/main",
        boot="true",
        github_token="",
        cache_limit_gb="20",
    )
    for save_step in (
        "exact-lookup",
        "measure",
        "capacity-guard",
        "cache-save",
        "Prune superseded Android SDK caches (main only)",
    ):
        assert save_step not in no_token_steps


def test_action_and_workflow_consistency():
    action_path = Path(os.environ["ANDROID_EMULATOR_ACTION_PATH"])
    wf_path = Path(os.environ["ANDROID_EMULATOR_WORKFLOW_PATH"])

    raw_action = action_path.read_text(encoding="utf-8")
    assert "system.img" in raw_action
    assert "fails emulator boot loudly" in raw_action

    action = yaml.safe_load(raw_action)
    steps = action["runs"]["steps"]

    cache_steps = [
        s
        for s in steps
        if isinstance(s.get("uses"), str) and s["uses"].startswith("actions/cache")
    ]
    assert len(cache_steps) == 5
    paths = [s["with"]["path"] for s in cache_steps]
    assert all(p == paths[0] for p in paths)
    sha_re = re.compile(r"^actions/cache(?:/(?:restore|save))?@[0-9a-f]{40}$")
    for s in cache_steps:
        assert sha_re.fullmatch(s["uses"]), f"unpinned uses: {s['uses']}"

    warm_lookup = next(s for s in cache_steps if s.get("id") == "warm-lookup")
    assert warm_lookup["with"].get("lookup-only") is True
    assert "restore-keys" not in warm_lookup["with"]

    save_steps = [s for s in cache_steps if s["uses"].startswith("actions/cache/save@")]
    assert len(save_steps) == 1
    assert "github.ref == 'refs/heads/main'" in save_steps[0]["if"]
    assert "inputs.github-token != ''" in save_steps[0]["if"]
    assert "inputs.cache-limit-gb != ''" in save_steps[0]["if"]
    assert "||" not in save_steps[0]["if"]

    for step in steps:
        run_cmd = step.get("run")
        if run_cmd:
            assert "${{" not in run_cmd, (
                f"expression inside run: in step {step.get('name')}"
            )
            for match in re.finditer(r"python3\s+([^\s]+)", run_cmd):
                script_ref = match.group(1).strip("\"'")
                assert script_ref.startswith("${GITHUB_ACTION_PATH}/"), (
                    f"relative python3 script path {script_ref!r} in step {step.get('name')}"
                )

    wf = yaml.safe_load(wf_path.read_text(encoding="utf-8"))
    on_block = wf.get("on") if "on" in wf else wf.get(True)
    assert "main" in on_block["push"]["branches"]
    assert "schedule" in on_block
    assert "workflow_dispatch" in on_block
    job = wf["jobs"]["warm-android-emulator"]
    assert "github.ref == 'refs/heads/main'" in job["if"]
    warm_step = next(
        s for s in job["steps"] if s.get("uses") == "./.github/actions/android-emulator"
    )
    assert warm_step["with"]["boot"] == "false"
    assert "cache-limit-gb" in warm_step["with"]
    assert "github-token" in warm_step["with"]
