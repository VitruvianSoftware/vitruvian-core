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

"""Look for secrets with the gitleaks and the rules CI uses.

  bazel run //tools/secret-scan                     # this branch's commits that main lacks
  bazel run //tools/secret-scan -- --staged         # what a commit would record now
  bazel run //tools/secret-scan -- --range <a..b>   # a range of commits
  bazel run //tools/secret-scan -- --unpushed       # commits origin does not have yet

gitleaks is pinned in tools/tools.lock.json at the version CI's
tools/ci/secret-scan.sh downloads (the test fails if the two drift apart), and
the rules are the repo's .gitleaks.toml. //tools/git:commit and :push call this
before they record or publish anything.

`:secret-scan` is the Rust port (src/); secret-scan.sh stays as
`:secret-scan-sh` and as the file //tools/git runs from its runfiles. Both are
held to secret-scan_test.sh, and the parity test runs them side by side.
"""

# Hand-written: gazelle would generate targets for the parity test.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

# //tools/git runs this script from its own runfiles.
exports_files(["secret-scan.sh"])

sh_binary(
    name = "secret-scan-sh",
    srcs = ["secret-scan.sh"],
    data = [
        "//:.gitleaks.toml",
        "@multitool//tools/gitleaks",
    ],
    visibility = ["//visibility:public"],
    deps = ["@bazel_tools//tools/bash/runfiles"],
)

# The Rust port. serde_json reads gitleaks' report (only the file, line, rule
# and commit fields); --help is secret-scan.sh's own header, compiled in.
# Optimised in every build mode.
rust_library(
    name = "secret_scan_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    compile_data = ["secret-scan.sh"],
    crate_name = "secret_scan",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
        "@rules_rust//rust/runfiles",
    ],
)

rust_binary(
    name = "secret-scan",
    srcs = ["src/main.rs"],
    data = [
        "//:.gitleaks.toml",
        "@multitool//tools/gitleaks",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":secret_scan_lib"],
)

alias(
    name = "secret-scan-rs",
    actual = ":secret-scan",
    visibility = ["//visibility:public"],
)

alias(
    name = "secret_scan_rs",
    actual = ":secret-scan",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "secret_scan_lib_test",
    size = "small",
    crate = ":secret_scan_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

_TEST_DATA = [
    "//:.gitleaks.toml",
    "//tools:tools.lock.json",
    "//tools/ci:secret-scan.sh",
    "@multitool//tools/gitleaks",
]

# Throwaway repos and the real pinned gitleaks: no network, never the real repo.
sh_test(
    name = "secret-scan_test",
    size = "small",
    srcs = ["secret-scan_test.sh"],
    args = [
        "$(location secret-scan.sh)",
        "$(location //tools/ci:secret-scan.sh)",
        "$(location //tools:tools.lock.json)",
    ],
    data = ["secret-scan.sh"] + _TEST_DATA,
    deps = ["@bazel_tools//tools/bash/runfiles"],
)

# The same cases against the Rust binary, which finds gitleaks and the rules
# through runfiles exactly as `bazel run` does.
sh_test(
    name = "secret-scan-rs_test",
    size = "small",
    srcs = ["secret-scan_test.sh"],
    args = [
        "$(location :secret-scan)",
        "$(location //tools/ci:secret-scan.sh)",
        "$(location //tools:tools.lock.json)",
    ],
    data = [":secret-scan"] + _TEST_DATA,
    deps = ["@bazel_tools//tools/bash/runfiles"],
)

# secret-scan.sh and :secret-scan side by side with the real pinned gitleaks:
# exit code, stdout and stderr must match in every mode and failure.
py_test(
    name = "secret_scan_rs_parity_test",
    size = "medium",
    srcs = ["secret_scan_rs_parity_test.py"],
    data = [
        "secret-scan.sh",
        ":secret-scan",
        "//:.gitleaks.toml",
        "@multitool//tools/gitleaks",
    ],
    env = {
        "GITLEAKS_BIN": "$(rootpath @multitool//tools/gitleaks)",
        "GITLEAKS_RULES": "$(rootpath //:.gitleaks.toml)",
        "SECRET_SCAN_RS": "$(rootpath :secret-scan)",
        "SECRET_SCAN_SH": "$(rootpath secret-scan.sh)",
    },
    main = "secret_scan_rs_parity_test.py",
)
