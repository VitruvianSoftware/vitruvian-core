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

"""Website utilities and catalog automation for vitruviansoftware.dev."""

# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

py_binary(
    name = "sync-downloads-py",
    srcs = ["sync_downloads.py"],
    imports = ["."],
    main = "sync_downloads.py",
    visibility = ["//visibility:public"],
)

py_test(
    name = "sync_downloads_test",
    srcs = ["sync_downloads_test.py"],
    deps = [":sync-downloads-py"],
)

# The same tool in Rust, standard library only: no crates, so it carries
# what it needs of Python by hand (src/json.rs, src/pyre.rs for the script's
# regular expressions, src/difflib.rs, src/argparse.rs). The HTTPS fallback
# runs curl, since std has no TLS; `gh api` is tried first, as in Python.
rust_library(
    name = "sync_downloads_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "sync_downloads",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "sync-downloads",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":sync_downloads_lib"],
)

alias(
    name = "sync_downloads",
    actual = ":sync-downloads",
    visibility = ["//visibility:public"],
)

alias(
    name = "sync-downloads-rs",
    actual = ":sync-downloads",
    visibility = ["//visibility:public"],
)

alias(
    name = "sync_downloads_rs",
    actual = ":sync-downloads",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "sync_downloads_lib_test",
    size = "small",
    crate = ":sync_downloads_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Holds the Rust binary to the Python script: both run as programs against
# a fake `gh` and the same catalogs, comparing exit codes, stdout, stderr,
# the catalog left behind and the API calls made.
py_test(
    name = "sync_downloads_rs_parity_test",
    size = "small",
    srcs = [
        "sync_downloads.py",
        "sync_downloads_rs_parity_test.py",
        "sync_downloads_test.py",
    ],
    # testdata/downloads.yml: a copy of the site's catalog, so the test
    # edits a real one without reaching into the site's package.
    data = [
        "testdata/downloads.yml",
        ":sync-downloads",
    ],
    env = {"SYNC_DOWNLOADS_RS": "$(rootpath :sync-downloads)"},
    imports = ["."],
    main = "sync_downloads_rs_parity_test.py",
)
