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

# Asserts that a rules_itest Redis service listens on 127.0.0.1 only, never
# the wildcard. svcinit reserves autoassigned ports on 127.0.0.1, so a service
# that also binds "*" / "::*" can lose the port to a socket svcinit never
# checked for. Consumed as the `test` of a service_test (see
# //apps/suites/tabula/api:redis_loopback_test).

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "check_loopback_lib",
    srcs = ["src/lib.rs"],
    crate_name = "check_loopback",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "check-loopback",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":check_loopback_lib"],
)

# The label consumers use. An alias, so the binary itself can carry a
# kebab-case name (//tools/lint-naming BZL001).
alias(
    name = "check_loopback",
    actual = ":check-loopback",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "check_loopback_lib_test",
    size = "small",
    crate = ":check_loopback_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "redis_lib_test",
    tests = [":check_loopback_lib_test"],
)

test_suite(
    name = "check-loopback_test",
    tests = [":check_loopback_lib_test"],
)

test_suite(
    name = "ensure_test",
    tests = [":check_loopback_lib_test"],
)
