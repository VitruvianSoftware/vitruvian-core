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
#
# `:run_postgres` and `:check_postgres` are the Rust port (src/); the scripts
# stay as `:run-postgres-sh` and `:check-postgres-sh`. rules_itest runs an
# exe straight from runfiles without a target's `args`, so each binary has its
# own thin entry point in src/bin/ over the one library. Nothing here reads
# or writes JSON, so the crate takes std only.

# Hand-written: gazelle would generate targets for the parity test.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files([
    "check-postgres.sh",
    "run-postgres.sh",
])

sh_binary(
    name = "run-postgres-sh",
    srcs = ["run-postgres.sh"],
    data = ["//tools/testinfra:pg_dist"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "check-postgres-sh",
    srcs = ["check-postgres.sh"],
    data = ["//tools/testinfra:pg_isready_bin"],
    visibility = ["//visibility:public"],
)

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

# One contract, both implementations, with stand-in initdb/postgres/pg_isready.
sh_test(
    name = "postgres_test",
    size = "small",
    srcs = ["postgres_test.sh"],
    args = [
        "$(location run-postgres.sh)",
        "$(location check-postgres.sh)",
    ],
    data = [
        "check-postgres.sh",
        "run-postgres.sh",
    ],
)

sh_test(
    name = "postgres-rs_test",
    size = "small",
    srcs = ["postgres_test.sh"],
    args = [
        "$(location :run-postgres)",
        "$(location :check-postgres)",
    ],
    data = [
        ":check-postgres",
        ":run-postgres",
    ],
)

# The scripts and the binaries side by side: exit status, stdout, stderr and
# every argument and variable the stand-ins receive must match.
py_test(
    name = "postgres_rs_parity_test",
    size = "medium",
    srcs = ["postgres_rs_parity_test.py"],
    data = [
        "check-postgres.sh",
        "run-postgres.sh",
        ":check-postgres",
        ":run-postgres",
    ],
    env = {
        "CHECK_POSTGRES_RS": "$(rootpath :check-postgres)",
        "CHECK_POSTGRES_SH": "$(rootpath check-postgres.sh)",
        "RUN_POSTGRES_RS": "$(rootpath :run-postgres)",
        "RUN_POSTGRES_SH": "$(rootpath run-postgres.sh)",
    },
    main = "postgres_rs_parity_test.py",
)
