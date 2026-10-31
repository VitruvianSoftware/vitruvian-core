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

"""The API half of standing up a per-agent GitHub App identity.

  bazel run //tools/agent-app -- convert <manifest-code> <out.pem>
  bazel run //tools/agent-app -- installations <app-id> <key.pem>
  bazel run //tools/agent-app -- repos <app-id> <key.pem> <installation-id>
  bazel run //tools/agent-app -- token <app-id> <key.pem> <installation-id>

Every agent pushes and merges as one human account, so PR authorship is not
attribution and no agent can approve another's work -- GitHub blocks
self-approval and every PR is self-authored from its point of view. The fix is
one GitHub App per agent; see docs/guides/agent-github-identities.md.

App CREATION is the one part that cannot live here. GitHub's Apps REST API has
fourteen endpoints and none of them creates an App: the only path is the
App-manifest flow, whose final step IS an API call (`convert`, below) but whose
`code` exists only after a signed-in human approves the handshake in a browser.
So the manual part is two clicks per agent and everything either side of them is
a target here -- which is the point, because these are the steps someone will
otherwise do by hand at 1am and mis-remember afterwards.

The runbook these implement is docs/guides/creating-an-agent-github-app.md.
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

# The tool, in Rust (src/agent_app/, built into permission_drift_lib, the
# package's one rust_library).
rust_binary(
    name = "agent-app",
    srcs = ["src/bin/agent_app.rs"],
    data = [
        "agents.tsv",
        "permissions.tsv",
        "workflow-allowlist.txt",
        # branch-delete's gate.
        "//tools/landed",
        "//tools/landed:landed.sh",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":permission_drift_lib"],
)

# agent-app.sh is no longer a source file: this genrule generates it, a two-line
# launcher that execs the Rust `:agent-app` beside it. //tools/git still runs it
# from runfiles (`_main/tools/agent-app/agent-app.sh`, overridable with
# AGENT_APP), and //tools/pipeline/verifiedrun is handed its path with
# `--agent-app=$(rlocationpath :agent-app.sh)`.
genrule(
    name = "agent_app_sh_shim",
    srcs = [":agent-app"],
    outs = ["agent-app.sh"],
    cmd = "printf '%s\\n' '#!/usr/bin/env bash' 'exec \"$$(cd \"$$(dirname \"$${BASH_SOURCE[0]}\")\" && pwd)/agent-app\" \"$$@\"' > $@ && chmod +x $@",
    executable = True,
    visibility = ["//visibility:public"],
)

alias(
    name = "agent-app-sh",
    actual = ":agent-app",
    visibility = ["//visibility:public"],
)

test_suite(
    name = "agent-app_test",
    tests = [":permission_drift_lib_test"],
)

test_suite(
    name = "agent_app_test",
    tests = [":permission_drift_lib_test"],
)

test_suite(
    name = "permission_drift_test",
    tests = [":permission_drift_lib_test"],
)

# The same check in Rust, standard library only (primary `:permission-drift`):
# the same command line, requests, report and exit codes. It carries what it
# needs of Python by hand: src/json.rs (json.loads and ==), src/argparse.rs,
# src/http.rs (urllib's errors and redirect rules; https:// runs curl, since
# std has no TLS). Optimised in every build mode.
#
# It also carries agent_app (src/agent_app/), the Rust `:agent-app` above: a
# package gets one rust_library (//tools/lint-naming), so the two share it.
# agent_app reads GitHub's JSON with serde_json and reuses shell-compat's bash
# behaviours.
rust_library(
    name = "permission_drift_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = [
            "src/main.rs",
            "src/bin/**",
        ],
    ),
    crate_name = "permission_drift",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "permission-drift",
    srcs = ["src/main.rs"],
    data = [
        "agents.tsv",
        "permissions.tsv",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":permission_drift_lib"],
)

# The #[cfg(test)] unit tests in src/: every case in permission_drift_test,
# on a fake GitHub, plus the HTTP client against a local socket; and
# agent_app's argument rules, encodings and jq programs (src/agent_app/tests.rs).
rust_test(
    name = "permission_drift_lib_test",
    size = "small",
    crate = ":permission_drift_lib",
    data = [
        "agents.tsv",
        "permissions.tsv",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)
