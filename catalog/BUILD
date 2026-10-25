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

# The tool catalog: tools.json, the list VitruvianSoftware curates by pull
# request, its schema, and the checks every change to it passes. README.md
# says what listing means and what a pull request must hold.

# Written by hand, like tools/sync-downloads: gazelle would name a library
# after the folder and clash with the targets below.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_library", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

exports_files([
    "catalog.schema.json",
    "public-key.txt",
    "tools.json",
])

py_library(
    name = "rules",
    srcs = ["catalog_rules.py"],
    imports = ["."],
)

# The file against its schema and its rules, with no network. Runs on every
# pull request in the build-test lane, as every test under //... does.
py_test(
    name = "catalog_test",
    size = "small",
    srcs = ["catalog_test.py"],
    data = [
        "catalog.schema.json",
        "public-key.txt",
        "tools.json",
        "//apps/desktop/vitruvian:Sources/Vitruvian/Services/Platform/External/Catalogue/CatalogueSigning.swift",
    ],
    deps = [
        ":rules",
        "@pip//jsonschema",
    ],
)

py_library(
    name = "signing",
    srcs = ["signing.py"],
    imports = ["."],
    deps = ["@pip//cryptography"],
)

# The Python reference: //catalog:sign is the Rust port (below).
# CATALOG_SIGNING_KEY=<base64> bazel run //catalog:sign-py -- --out <folder>
#
# Run by .github/workflows/catalog-publish.yaml after a change to tools.json
# merges. It refuses a key whose public half is not public-key.txt.
py_binary(
    name = "sign-py",
    srcs = ["sign.py"],
    data = [
        "public-key.txt",
        "tools.json",
    ],
    main = "sign.py",
    deps = [":signing"],
)

py_test(
    name = "signing_test",
    size = "small",
    srcs = ["signing_test.py"],
    data = [
        "public-key.txt",
        "sign.py",
    ],
    deps = [":signing"],
)

# Run by .github/workflows/catalog-check.yaml, with the network, on a pull
# request that changes this folder.
py_binary(
    name = "check-downloads-py",
    srcs = ["check_downloads.py"],
    main = "check_downloads.py",
    deps = [":rules"],
)

py_test(
    name = "check_downloads_test",
    size = "small",
    srcs = ["check_downloads_test.py"],
    deps = [
        ":check-downloads-py",
        ":rules",
    ],
)

# bazel run //catalog:rehearse
#
# Serves a rehearsal catalog on 127.0.0.1, signed with a key made for the
# run, for the checks by hand in a --define=vitruvian_sample_tool=true build.
py_binary(
    name = "rehearse-py",
    srcs = ["rehearse.py"],
    main = "rehearse.py",
    deps = [":signing"],
)

py_test(
    name = "rehearse_test",
    size = "small",
    srcs = ["rehearse_test.py"],
    deps = [
        ":rehearse-py",
        ":rules",
        ":signing",
    ],
)

# bazel run //catalog:bump -- --id dev.vitruvian.homespeaker --tag home-speaker-v1.20.0
#
# Updates one entry, and _data/tools.yml, from one release, after checking
# its zip against GitHub's record and its .sha256 and reading its manifest.
# sources.json says which release updates which entry. Run by
# .github/workflows/catalog-bump.yaml, which opens the pull request; its
# `plan` (python3 catalog/bump.py plan) runs there without Bazel.
py_binary(
    name = "bump-py",
    srcs = ["bump.py"],
    data = [
        "catalog.schema.json",
        "sources.json",
        "tools.json",
    ],
    main = "bump.py",
    deps = [
        ":rules",
        "//tools/sync-site-tools:catalogue",
        "@pip//jsonschema",
    ],
)

# Fixture zips made in the test, with no network.
py_test(
    name = "bump_test",
    size = "small",
    srcs = ["bump_test.py"],
    data = [
        "catalog.schema.json",
        "public-key.txt",
        "sources.json",
        "testdata/Info.plist",
        "testdata/sources.json",
        "testdata/tools.json",
        "tools.json",
        "//apps/desktop/vitruvian:Resources/Info.plist",
    ],
    deps = [
        ":bump-py",
        ":rules",
        "//tools/sync-site-tools:catalogue",
        "@pip//jsonschema",
    ],
)

# catalog-bump starts when a tool's release workflow finishes: its
# workflow_run list must be the releaseWorkflow column of sources.json, and
# every tool released from this repository must have one. Reads every
# workflow, since workflow_run matches a workflow by its name: line.
py_test(
    name = "release_trigger_test",
    size = "small",
    srcs = ["release_trigger_test.py"],
    data = [
        "sources.json",
        "//:workflow_files",
    ],
    deps = ["@pip//pyyaml"],
)

# --- The Rust port ---------------------------------------------------------------
#
# One library holds the four tools; each binary is a thin entrypoint. The
# Python scripts stay the reference (catalog-bump.yaml still runs bump.py
# plan without Bazel), and :catalog_rs_parity_test holds the two to the
# same output.

rust_library(
    name = "catalog_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/bin/**"],
    ),
    crate_name = "catalog",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

# The four tools. Each reads and writes what its .py does; the -py targets
# above keep the scripts runnable, and -rs names the port explicitly.
rust_binary(
    name = "sign",
    srcs = ["src/bin/sign.rs"],
    data = [
        "public-key.txt",
        "tools.json",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":catalog_lib"],
)

rust_binary(
    name = "check-downloads",
    srcs = ["src/bin/check_downloads.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":catalog_lib"],
)

rust_binary(
    name = "rehearse",
    srcs = ["src/bin/rehearse.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":catalog_lib"],
)

rust_binary(
    name = "bump",
    srcs = ["src/bin/bump.rs"],
    data = [
        "catalog.schema.json",
        "sources.json",
        "tools.json",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":catalog_lib"],
)

alias(
    name = "sign-rs",
    actual = ":sign",
)

alias(
    name = "check-downloads-rs",
    actual = ":check-downloads",
)

alias(
    name = "rehearse-rs",
    actual = ":rehearse",
)

alias(
    name = "bump-rs",
    actual = ":bump",
)

rust_test(
    name = "catalog_lib_test",
    size = "small",
    compile_data = glob(["testdata/**"]) + [
        "catalog.schema.json",
        "public-key.txt",
        "tools.json",
    ],
    crate = ":catalog_lib",
    data = [
        "catalog.schema.json",
        "public-key.txt",
        "tools.json",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# The port against its scripts: the same inputs through both, the same
# output, files and exit status out. See the file for what it covers.
py_test(
    name = "catalog_rs_parity_test",
    size = "medium",
    srcs = ["catalog_rs_parity_test.py"],
    data = [
        "bump.py",
        "catalog.schema.json",
        "check_downloads.py",
        "public-key.txt",
        "rehearse.py",
        "sign.py",
        "sources.json",
        "testdata/Info.plist",
        "testdata/sources.json",
        "testdata/tools.json",
        "tools.json",
        ":bump",
        ":check-downloads",
        ":rehearse",
        ":sign",
    ],
    env = {
        "BUMP_RS": "$(rootpath :bump)",
        "CHECK_DOWNLOADS_RS": "$(rootpath :check-downloads)",
        "REHEARSE_RS": "$(rootpath :rehearse)",
        "SIGN_RS": "$(rootpath :sign)",
    },
    deps = [
        ":rules",
        ":signing",
        "//tools/sync-site-tools:catalogue",
        "@pip//cryptography",
        "@pip//jsonschema",
    ],
)
