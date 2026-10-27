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

"""Did this work actually land on main?

  bazel run //tools/landed -- 1205                 # a PR number
  bazel run //tools/landed -- claude/my-branch     # a branch
  bazel run //tools/landed -- da6612ad             # a local commit
  bazel run //tools/landed -- --branch my/branch          # safe to delete this local branch?
  bazel run //tools/landed -- --remote-branch my/branch   # ...this branch on origin?

`main` is squash-only (enforced by the repo-config ruleset), so a topic branch's
commits are REWRITTEN on merge and their SHAs are never ancestors of main. The
obvious `git merge-base --is-ancestor <branch-sha> origin/main` therefore reports
every merged PR as missing -- a false negative on work that is actually landed.
This resolves the durable identity (the PR number) to the squashed commit and
verifies THAT against origin/main.
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "landed_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "landed",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "landed",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":landed_lib"],
)

genrule(
    name = "landed_sh_shim",
    srcs = [":landed"],
    outs = ["landed.sh"],
    cmd = "printf '%s\\n' '#!/usr/bin/env bash' " +
          "'exec \"$$(cd \"$$(dirname \"$${BASH_SOURCE[0]}\")\" && pwd)/landed\" \"$$@\"' > $@ && chmod +x $@",
    executable = True,
    visibility = ["//visibility:public"],
)

alias(
    name = "landed-rs",
    actual = ":landed",
    visibility = ["//visibility:public"],
)

alias(
    name = "landed_rs",
    actual = ":landed",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "landed_lib_test",
    size = "small",
    crate = ":landed_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "landed_test",
    tests = [":landed_lib_test"],
)

test_suite(
    name = "landed-rs_test",
    tests = [":landed_lib_test"],
)
