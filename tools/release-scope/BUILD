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

# //tools/release-scope: does a pull request release a product its title does
# not name? release_scope.py says how it decides; the release-scope workflow
# runs it on every pull request.
#
# Hand-written: the test reads fixtures and one config from another package.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

py_binary(
    name = "release-scope-py",
    srcs = ["release_scope.py"],
    data = ["aliases.json"],
    main = "release_scope.py",
)

# Fixtures only, no network. The replay tests hold it to 13 October 2026; one
# of them reads the SDK's config as it is now, to show that letting a tool in
# through packages/vitruvian-sdk/consumers releases nothing.
py_test(
    name = "release_scope_test",
    size = "small",
    srcs = [
        "release_scope.py",
        "release_scope_test.py",
    ],
    data = [
        "aliases.json",
        "//:.github/workflows/release-scope.yaml",
        "//packages/vitruvian-sdk:release-please-config.json",
    ] + glob(["testdata/*.json"]),
    main = "release_scope_test.py",
)

# The same check in Rust, for speed (primary `:release-scope` binary). It takes
# no crate, not even serde_json: it must keep a JSON object's key order and
# read NaN, as Python's json does, and print Python's errors, so it carries its
# own reader (src/json.rs), and matches Python's regular expressions and
# argparse by hand. Optimised in every build mode.
rust_library(
    name = "release_scope_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "release_scope",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "release-scope",
    srcs = ["src/main.rs"],
    data = ["aliases.json"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":release_scope_lib"],
)

alias(
    name = "release_scope_rs",
    actual = ":release-scope",
)

rust_test(
    name = "release_scope_lib_test",
    size = "small",
    crate = ":release_scope_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Holds the Rust binary to the Python script: every case in
# release_scope_test.py, every fixture in testdata/, and inputs built to
# break them, run through both, comparing exit codes, stdout and stderr.
py_test(
    name = "release_scope_rs_parity_test",
    size = "small",
    srcs = [
        "gen_unicode_tables.py",
        "release_scope.py",
        "release_scope_rs_parity_test.py",
        "release_scope_test.py",
    ],
    data = [
        "aliases.json",
        "src/unicode_tables.rs",
        ":release-scope",
        "//:.github/workflows/release-scope.yaml",
        "//packages/vitruvian-sdk:release-please-config.json",
    ] + glob(["testdata/*.json"]),
    env = {"RELEASE_SCOPE_RS": "$(rootpath :release-scope)"},
    main = "release_scope_rs_parity_test.py",
)
