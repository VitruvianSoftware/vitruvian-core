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

# Hermetic per-test PostgreSQL: initdb into the service TMPDIR and run on the
# rules_itest-assigned loopback port. Consumed as itest_service exe (see
# //apps/suites/tabula/api).

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "postgres_lib",
    srcs = ["src/lib.rs"],
    crate_name = "postgres",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "run-postgres",
    srcs = ["src/bin/run_postgres.rs"],
    data = ["//tools/testinfra:pg_dist"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":postgres_lib"],
)

rust_binary(
    name = "check-postgres",
    srcs = ["src/bin/check_postgres.rs"],
    data = ["//tools/testinfra:pg_isready_bin"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":postgres_lib"],
)

# The labels consumers use. Aliases, so the binaries themselves can carry
# kebab-case names (//tools/lint-naming BZL001).
alias(
    name = "run_postgres",
    actual = ":run-postgres",
    visibility = ["//visibility:public"],
)

alias(
    name = "check_postgres",
    actual = ":check-postgres",
    visibility = ["//visibility:public"],
)

alias(
    name = "run-postgres-rs",
    actual = ":run-postgres",
    visibility = ["//visibility:public"],
)

alias(
    name = "run_postgres_rs",
    actual = ":run-postgres",
    visibility = ["//visibility:public"],
)

alias(
    name = "check-postgres-rs",
    actual = ":check-postgres",
    visibility = ["//visibility:public"],
)

alias(
    name = "check_postgres_rs",
    actual = ":check-postgres",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "postgres_lib_test",
    size = "small",
    crate = ":postgres_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "postgres_test",
    tests = [":postgres_lib_test"],
)

test_suite(
    name = "postgres-rs_test",
    tests = [":postgres_lib_test"],
)

test_suite(
    name = "ensure_test",
    tests = [":postgres_lib_test"],
)
