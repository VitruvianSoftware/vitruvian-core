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

"""The Tools section of vitruviansoftware.dev, copied from packages/vitruvian-sdk.

    bazel run //tools/sync-site-tools:sync       writes the copies (Rust)
    bazel run //tools/sync-site-tools:sync-py    the same, from sync.py
"""

# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_library", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

# The files the catalog's part is written from, and the file it writes.
SITE_FILES = [
    "//:.claude-plugin/marketplace.json",
    "//apps/desktop/antigravity/plugins/ext-marketplace:site_sources",
    "//apps/desktop/antigravity/plugins/gh-watch:site_sources",
    "//apps/desktop/antigravity/plugins/hookify:site_sources",
    "//apps/desktop/antigravity/plugins/live-context:site_sources",
    "//apps/desktop/antigravity/plugins/ralph-loop:site_sources",
    "//apps/desktop/antigravity/plugins/receipts-report:site_sources",
    "//apps/desktop/antigravity/plugins/savvy-fleet:site_sources",
    "//apps/desktop/antigravity/plugins/security-guidance:site_sources",
    "//apps/desktop/antigravity/plugins/worktree-band:site_sources",
    "//apps/web/vitruviansoftware-dev:.claude-plugin/marketplace.json",
    "//apps/web/vitruviansoftware-dev:_data/extensions.yml",
    "//apps/web/vitruviansoftware-dev:_data/tools.yml",
    "//apps/web/vitruviansoftware-dev:ai/catalog.json",
    "//catalog:catalog.schema.json",
    "//catalog:public-key.txt",
    "//catalog:tools.json",
]

# Everything sync reads and writes in the repository, for the tests.
SYNC_DATA = SITE_FILES + [
    "//apps/web/vitruviansoftware-dev:tools_pages",
    "//packages/vitruvian-sdk:release-please-config.json",
    "//packages/vitruvian-sdk:site_sources",
]

# The catalog's part alone, for //catalog:bump, which rewrites _data/tools.yml
# after it changes an entry.
py_library(
    name = "catalogue",
    srcs = ["catalogue.py"],
    imports = ["."],
    visibility = ["//catalog:__pkg__"],
)

# --- Rust port -----------------------------------------------------------
# src/ is sync.py, catalogue.py and registry.py in Rust: the same files, byte
# for byte, the same stdout, stderr and exit status. It takes only std, no
# crate, so Cargo.lock and MODULE.bazel stay as they are. src/unicode_tables.rs
# (from gen_unicode_tables.py) carries the character classes Python's str and
# re use. Optimised in every build mode.
rust_library(
    name = "sync_site_tools_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "sync_site_tools",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "sync",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":sync_site_tools_lib"],
)

alias(
    name = "sync-rs",
    actual = ":sync",
)

alias(
    name = "sync_rs",
    actual = ":sync",
)

# sync.py itself, which the Rust port is held to.
py_binary(
    name = "sync-py",
    srcs = [
        "catalogue.py",
        "registry.py",
        "sync.py",
    ],
    imports = ["."],
    main = "sync.py",
)

# The #[cfg(test)] unit tests in src/, and sync_test.py's tests that read the
# repository, run against the committed files.
rust_test(
    name = "sync_site_tools_lib_test",
    size = "small",
    crate = ":sync_site_tools_lib",
    data = SYNC_DATA,
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# The committed copies are what sync.py writes from the SDK's files now. Not
# `manual` and not tied to macOS: plain Python, so the Linux lane runs it,
# whenever the guide, the protocol's README, a hello sample, the catalog or
# a copy changes.
py_test(
    name = "in_sync_test",
    size = "small",
    srcs = ["sync_test.py"],
    data = SYNC_DATA,
    main = "sync_test.py",
    deps = [":sync-py"],
)

# sync.py and the Rust sync side by side: every case of sync_test.py, this
# repository's own files, and trees built to break them (Unicode, newlines,
# bad UTF-8 and JSON, wrong types, missing and unreadable files, odd plugin
# folders, write failures). Generated files, stdout, stderr and exit status
# must match byte for byte.
py_test(
    name = "sync_site_tools_rs_parity_test",
    size = "small",
    srcs = ["sync_site_tools_rs_parity_test.py"],
    data = SYNC_DATA + [
        "catalogue.py",
        "gen_unicode_tables.py",
        "registry.py",
        "src/unicode_tables.rs",
        "sync.py",
        "sync_test.py",
        ":sync",
    ],
    env = {"SYNC_RS": "$(rootpath :sync)"},
    main = "sync_site_tools_rs_parity_test.py",
    deps = [":sync-py"],
)
