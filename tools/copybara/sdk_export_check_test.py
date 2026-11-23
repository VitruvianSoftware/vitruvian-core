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

from __future__ import annotations

from pathlib import Path

import pytest
import sdk_export_check


def _write_tree(
    root: Path,
    cargo_files: dict[str, str],
    workflows: dict[str, str],
) -> None:
    for rel, content in cargo_files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
    wf_dir = root / ".github" / "workflows"
    wf_dir.mkdir(parents=True, exist_ok=True)
    for name, content in workflows.items():
        (wf_dir / name).write_text(content, encoding="utf-8")


def test_parse_rust_version() -> None:
    assert sdk_export_check.parse_rust_version("1.98") == (1, 98, 0)
    assert sdk_export_check.parse_rust_version("1.98.1") == (1, 98, 1)
    assert sdk_export_check.parse_rust_version(
        "1.100.0"
    ) > sdk_export_check.parse_rust_version("1.98")  # type: ignore[operator]
    assert sdk_export_check.parse_rust_version(
        "1.75"
    ) < sdk_export_check.parse_rust_version("1.98")  # type: ignore[operator]
    assert sdk_export_check.parse_rust_version("stable") is None
    assert sdk_export_check.parse_rust_version("$RUST") is None
    assert sdk_export_check.parse_rust_version("${{ matrix.rust }}") is None


def test_verify_workflow_rust_versions_passes(tmp_path: Path) -> None:
    _write_tree(
        tmp_path,
        cargo_files={
            "kits/rust/Cargo.toml": '[package]\nname = "kit"\nrust-version = "1.98"\n',
            "verification/Cargo.toml": '[package]\nname = "v"\nrust-version = "1.98"\n',
        },
        workflows={
            "ci.yml": (
                "jobs:\n"
                "  checks:\n"
                "    steps:\n"
                "      - run: |\n"
                "          rustup toolchain install 1.98.1 --profile minimal\n"
                "          rustup default 1.98.1\n"
            ),
            "kits.yml": (
                "jobs:\n"
                "  rust:\n"
                "    strategy:\n"
                "      matrix:\n"
                '        rust: ["1.98.1", "stable"]\n'
                "    steps:\n"
                '      - run: rustup toolchain install "$RUST" --profile minimal\n'
            ),
        },
    )
    sdk_export_check.verify_workflow_rust_versions(tmp_path)


def test_verify_workflow_rust_versions_flags_all_lower_versions(tmp_path: Path) -> None:
    _write_tree(
        tmp_path,
        cargo_files={
            "kits/rust/Cargo.toml": '[package]\nname = "kit"\nrust-version = "1.75"\n',
            "verification/Cargo.toml": '[package]\nname = "v"\nrust-version = "1.98"\n',
        },
        workflows={
            "ci.yml": (
                "jobs:\n"
                "  checks:\n"
                "    steps:\n"
                "      - run: |\n"
                "          # rustup default 1.70.0\n"
                "          rustup toolchain install 1.75.0 --profile minimal\n"
                "          rustup default 1.75.0\n"
            ),
            "kits.yml": (
                "jobs:\n"
                "  rust:\n"
                "    strategy:\n"
                "      matrix:\n"
                '        rust: ["1.75", "stable"]\n'
                "  block:\n"
                "    strategy:\n"
                "      matrix:\n"
                "        rust:\n"
                '          - "1.80"\n'
                "          - stable\n"
            ),
        },
    )
    with pytest.raises(RuntimeError) as exc_info:
        sdk_export_check.verify_workflow_rust_versions(tmp_path)

    msg = str(exc_info.value)
    assert (
        ".github/workflows/ci.yml:6: Rust version 1.75.0 is lower than required rust-version 1.98 (from verification/Cargo.toml)"
        in msg
    )
    assert (
        ".github/workflows/ci.yml:7: Rust version 1.75.0 is lower than required rust-version 1.98 (from verification/Cargo.toml)"
        in msg
    )
    assert (
        ".github/workflows/kits.yml:5: Rust version 1.75 is lower than required rust-version 1.98 (from verification/Cargo.toml)"
        in msg
    )
    assert (
        ".github/workflows/kits.yml:10: Rust version 1.80 is lower than required rust-version 1.98 (from verification/Cargo.toml)"
        in msg
    )
    assert "1.70.0" not in msg


def test_dtolnay_ref_below_floor_fails(tmp_path: Path) -> None:
    _write_tree(
        tmp_path,
        cargo_files={
            "kits/rust/Cargo.toml": '[package]\nname = "kit"\nrust-version = "1.98"\n',
        },
        workflows={
            "ci.yml": (
                "jobs:\n"
                "  checks:\n"
                "    steps:\n"
                "      - uses: dtolnay/rust-toolchain@1.97.0\n"
            ),
        },
    )
    with pytest.raises(RuntimeError) as exc_info:
        sdk_export_check.verify_workflow_rust_versions(tmp_path)

    msg = str(exc_info.value)
    assert (
        ".github/workflows/ci.yml:4: Rust version 1.97.0 is lower than required rust-version 1.98"
        in msg
    )


def test_dtolnay_with_toolchain_below_floor_fails(tmp_path: Path) -> None:
    _write_tree(
        tmp_path,
        cargo_files={
            "kits/rust/Cargo.toml": '[package]\nname = "kit"\nrust-version = "1.98"\n',
        },
        workflows={
            "ci.yml": (
                "jobs:\n"
                "  checks:\n"
                "    steps:\n"
                "      - uses: dtolnay/rust-toolchain@master\n"
                "        with:\n"
                "          toolchain: 1.97\n"
            ),
        },
    )
    with pytest.raises(RuntimeError) as exc_info:
        sdk_export_check.verify_workflow_rust_versions(tmp_path)

    msg = str(exc_info.value)
    assert (
        ".github/workflows/ci.yml:6: Rust version 1.97 is lower than required rust-version 1.98"
        in msg
    )


@pytest.mark.parametrize("channel", ["stable", "beta", "nightly"])
def test_dtolnay_channel_refs_pass(tmp_path: Path, channel: str) -> None:
    _write_tree(
        tmp_path,
        cargo_files={
            "kits/rust/Cargo.toml": '[package]\nname = "kit"\nrust-version = "1.98"\n',
        },
        workflows={
            "ci.yml": (
                "jobs:\n"
                "  checks:\n"
                "    steps:\n"
                f"      - uses: dtolnay/rust-toolchain@{channel}\n"
            ),
        },
    )
    sdk_export_check.verify_workflow_rust_versions(tmp_path)


@pytest.mark.parametrize(
    "action",
    [
        "actions-rs/toolchain@v1",
        "actions-rust-lang/setup-rust-toolchain@v1",
    ],
)
def test_unknown_toolchain_action_fails_closed(tmp_path: Path, action: str) -> None:
    _write_tree(
        tmp_path,
        cargo_files={
            "kits/rust/Cargo.toml": '[package]\nname = "kit"\nrust-version = "1.98"\n',
        },
        workflows={
            "ci.yml": (f"jobs:\n  checks:\n    steps:\n      - uses: {action}\n"),
        },
    )
    with pytest.raises(RuntimeError) as exc_info:
        sdk_export_check.verify_workflow_rust_versions(tmp_path)

    msg = str(exc_info.value)
    assert ".github/workflows/ci.yml:4:" in msg


def test_unparseable_rustup_var_without_matrix_fails_closed(tmp_path: Path) -> None:
    _write_tree(
        tmp_path,
        cargo_files={
            "kits/rust/Cargo.toml": '[package]\nname = "kit"\nrust-version = "1.98"\n',
        },
        workflows={
            "ci.yml": (
                "jobs:\n"
                "  checks:\n"
                "    steps:\n"
                '      - run: rustup toolchain install "$WHATEVER" --profile minimal\n'
            ),
        },
    )
    with pytest.raises(RuntimeError) as exc_info:
        sdk_export_check.verify_workflow_rust_versions(tmp_path)

    msg = str(exc_info.value)
    assert ".github/workflows/ci.yml:4:" in msg
    assert "$WHATEVER" in msg


def test_dtolnay_matrix_toolchain_passes_with_matrix(tmp_path: Path) -> None:
    _write_tree(
        tmp_path,
        cargo_files={
            "kits/rust/Cargo.toml": '[package]\nname = "kit"\nrust-version = "1.98"\n',
        },
        workflows={
            "kits.yml": (
                "jobs:\n"
                "  rust:\n"
                "    strategy:\n"
                "      matrix:\n"
                '        rust: ["1.98.1", "stable"]\n'
                "    steps:\n"
                "      - uses: dtolnay/rust-toolchain@master\n"
                "        with:\n"
                "          toolchain: ${{ matrix.rust }}\n"
            ),
        },
    )
    sdk_export_check.verify_workflow_rust_versions(tmp_path)


def test_dtolnay_matrix_toolchain_without_matrix_fails_closed(tmp_path: Path) -> None:
    _write_tree(
        tmp_path,
        cargo_files={
            "kits/rust/Cargo.toml": '[package]\nname = "kit"\nrust-version = "1.98"\n',
        },
        workflows={
            "kits.yml": (
                "jobs:\n"
                "  rust:\n"
                "    steps:\n"
                "      - uses: dtolnay/rust-toolchain@master\n"
                "        with:\n"
                "          toolchain: ${{ matrix.rust }}\n"
            ),
        },
    )
    with pytest.raises(RuntimeError) as exc_info:
        sdk_export_check.verify_workflow_rust_versions(tmp_path)

    msg = str(exc_info.value)
    assert ".github/workflows/kits.yml:6:" in msg


def test_dtolnay_unparseable_ref_without_toolchain_fails_closed(tmp_path: Path) -> None:
    _write_tree(
        tmp_path,
        cargo_files={
            "kits/rust/Cargo.toml": '[package]\nname = "kit"\nrust-version = "1.98"\n',
        },
        workflows={
            "ci.yml": (
                "jobs:\n"
                "  checks:\n"
                "    steps:\n"
                "      - uses: dtolnay/rust-toolchain@master\n"
            ),
        },
    )
    with pytest.raises(RuntimeError) as exc_info:
        sdk_export_check.verify_workflow_rust_versions(tmp_path)

    msg = str(exc_info.value)
    assert ".github/workflows/ci.yml:4:" in msg
