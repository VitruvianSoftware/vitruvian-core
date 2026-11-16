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

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# Installs vrelay as a signed LaunchAgent for the person running it:
#   bazel run //apps/suites/vitruvian-relay/connector/scripts:install [-- --unsigned] [-- --node <path>]
#   bazel run //apps/suites/vitruvian-relay/connector/scripts:uninstall
# What goes where is in src/lib.rs.

_DEPS = [
    "//apps/suites/vitruvian-relay/connector:vitruvian_relay_connector",
    "@vitruvian_relay_crates//:libc",
    "@vitruvian_relay_crates//:serde_json",
]

rust_library(
    name = "vrelay_install",
    srcs = [
        "src/layout.rs",
        "src/lib.rs",
        "src/tests.rs",
    ],
    compile_data = ["com.vitruvian.vrelay.plist"],
    crate_name = "vrelay_install",
    crate_root = "src/lib.rs",
    edition = "2021",
    deps = _DEPS,
)

rust_binary(
    name = "install",
    srcs = ["src/main.rs"],
    crate_root = "src/main.rs",
    data = [
        "com.vitruvian.vrelay.plist",
        "//apps/suites/vitruvian-relay/connector:vrelay",
        "//apps/suites/vitruvian-relay/connector/dc:desktop_commander",
    ],
    edition = "2021",
    deps = _DEPS + [":vrelay_install"],
)

rust_binary(
    name = "uninstall",
    srcs = ["src/main.rs"],
    crate_root = "src/main.rs",
    edition = "2021",
    rustc_env = {"VRELAY_SCRIPT": "uninstall"},
    deps = _DEPS + [":vrelay_install"],
)

# Against fakes in a temporary home: no launchd, no keychain, no npm fetch.
rust_test(
    name = "vrelay_install_test",
    size = "small",
    crate = ":vrelay_install",
)

test_suite(
    name = "unit_tests",
    tests = [":vrelay_install_test"],
)

# The placement against the real pinned package (a ~600-package fetch on a
# cold cache). It builds only layout.rs, so it runs with dc/'s own unit
# (connector/dc/BUILD), not on every connector change.
rust_test(
    name = "package_layout_test",
    size = "medium",
    srcs = [
        "src/layout.rs",
        "src/package_test.rs",
    ],
    crate_root = "src/package_test.rs",
    data = ["//apps/suites/vitruvian-relay/connector/dc:desktop_commander"],
    edition = "2021",
    visibility = ["//apps/suites/vitruvian-relay/connector/dc:__pkg__"],
)

pipeline_unit(
    name = "vrelay-install",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [":unit_tests"],
    tier = "L1",
    timeout_minutes = 15,
)
