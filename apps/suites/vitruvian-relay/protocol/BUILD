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

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# JSON frames between the relay and the vrelay connector.
package(default_visibility = ["//apps/suites/vitruvian-relay:__subpackages__"])

_CRATES = [
    "@vitruvian_relay_crates//:serde",
    "@vitruvian_relay_crates//:serde_json",
]

rust_library(
    name = "vitruvian_relay_protocol",
    srcs = ["src/lib.rs"],
    crate_name = "vitruvian_relay_protocol",
    crate_root = "src/lib.rs",
    edition = "2021",
    deps = _CRATES,
)

rust_test(
    name = "vitruvian_relay_protocol_test",
    size = "small",
    crate = ":vitruvian_relay_protocol",
)

test_suite(
    name = "unit_tests",
    tests = [":vitruvian_relay_protocol_test"],
)

pipeline_unit(
    name = "vitruvian-relay-protocol",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [":unit_tests"],
    tier = "L1",
    timeout_minutes = 15,
)
