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

"""Generate per-harness subagent files from .agents/roster/.

  bazel run //tools/agent-roster -- --check
  bazel run //tools/agent-roster -- --write
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "agent_roster_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "agent_roster",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "agent-roster",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":agent_roster_lib"],
)

rust_binary(
    name = "write",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_env = {"AGENT_ROSTER_DEFAULT_MODE": "write"},
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":agent_roster_lib"],
)

genrule(
    name = "agent_roster_sh_shim",
    srcs = [":agent-roster"],
    outs = ["agent-roster.sh"],
    cmd = "printf '%s\\n' '#!/usr/bin/env bash' " +
          "'exec \"$$(cd \"$$(dirname \"$${BASH_SOURCE[0]}\")\" && pwd)/agent-roster\" \"$$@\"' > $@ && chmod +x $@",
    executable = True,
    visibility = ["//visibility:public"],
)

rust_test(
    name = "agent_roster_lib_test",
    size = "small",
    crate = ":agent_roster_lib",
    data = [
        "//:.agents/roster/skills/orchestrate/antigravity.md",
        "//:.agents/roster/skills/orchestrate/claude-code.md",
        "//:.agents/roster/skills/orchestrate/opencode.md",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "agent_roster_test",
    tests = [":agent_roster_lib_test"],
)
