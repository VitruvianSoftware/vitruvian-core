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
//tools/ci:secret_scan downloads (//tools/ci:secret_scan_test fails if the two
drift apart), and
the rules are the repo's .gitleaks.toml. //tools/git:commit and :push call this
before they record or publish anything.
"""

# Hand-written: gazelle would generate targets for the package.
# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

# The Rust implementation. serde_json reads gitleaks' report (only the file,
# line, rule and commit fields). Optimised in every build mode.
rust_library(
    name = "secret_scan_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
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

# //tools/git invokes `_main/tools/secret-scan/secret-scan.sh` via `bash` from
# its runfiles; this generated launcher forwards directly to the Rust binary.
genrule(
    name = "secret_scan_sh_shim",
    srcs = [":secret-scan"],
    outs = ["secret-scan.sh"],
    cmd = "printf '%s\\n' '#!/usr/bin/env bash' 'exec \"$$(cd \"$$(dirname \"$${BASH_SOURCE[0]}\")\" && pwd)/secret-scan\" \"$$@\"' > $@ && chmod +x $@",
    executable = True,
    visibility = ["//visibility:public"],
)

rust_test(
    name = "secret_scan_lib_test",
    size = "small",
    crate = ":secret_scan_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "secret-scan_test",
    tests = [":secret_scan_lib_test"],
)

# agent-guard reads this file to check its refusal advice names a real target
# (//tools/agent-guard:pending_target_files).
exports_files(
    ["BUILD"],
    visibility = ["//tools/agent-guard:__pkg__"],
)
