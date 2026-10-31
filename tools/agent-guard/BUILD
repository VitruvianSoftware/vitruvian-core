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

"""agent-guard: a Claude Code and Antigravity hook that keeps agents' repo and dev operations on Bazel targets.

It runs from the repo: .claude/settings.json and .agents/hooks.json call
hook.sh, which builds and runs the guard as it is on origin/main. A thin
per-user backstop covers sessions started outside the repo.

  bazel run //tools/agent-guard:install                  # install the backstop (once)
  bazel run //tools/agent-guard:install -- --check       # wiring, backstop and launcher OK?

See README.md.
"""

# Hand-written: the guard's crate is built two ways (here, and by hook.sh with
# plain rustc), and the tests' data is chosen by hand.
# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

# The launchers: hook.sh, and proposed-hook.sh while it waits for James to
# move it over hook.sh. A glob, so this file still loads once it has.
LAUNCHERS = glob(
    [
        "hook.sh",
        "proposed-hook.sh",
    ],
    allow_empty = True,
)

exports_files(LAUNCHERS + ["policy.json"])

# The guard's crate. hook.sh compiles the same src/ with plain `rustc -O`, so
# it stays standard-library only: no deps here either.
rust_library(
    name = "agent_guard_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "agent_guard",
    crate_root = "src/lib.rs",
    edition = "2021",
    # Optimised in every build mode, as hook.sh builds it: an unoptimised
    # guard is slow on megabyte commands.
    rustc_flags = ["-Copt-level=3"],
)

# The guard on its own. Not how it runs in practice (hook.sh builds
# origin/main's copy with the machine's rustc), but handy for trying a payload:
#   echo '{"tool_name":"Bash","cwd":"'$PWD'","tool_input":{"command":"git push"}}' | bazel run //tools/agent-guard
rust_binary(
    name = "agent-guard",
    srcs = ["src/main.rs"],
    # The name hook.sh gives it, and not the library's.
    crate_name = "agent_guard_hook",
    data = ["policy.json"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":agent_guard_lib"],
)

# Installs the per-user backstop (entries running the main checkout's hook.sh),
# migrating the old copied install; --check, --dry-run, --uninstall. Standard
# library only, like the guard.
rust_binary(
    name = "install",
    srcs = glob(["install/**/*.rs"]),
    crate_root = "install/main.rs",
    data = ["policy.json"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":agent_guard_lib"],
)

# The files the guard's "pending" targets name (classify.rs T_*): the refusal
# advice checks them to say whether a target exists yet. The tests fail if one
# is missing or no longer holds its target, so a deleted or renamed tool
# cannot leave every refusal claiming its replacement "is not in this checkout
# yet" (it did, for //tools/agent-app and //tools/worktree, after their
# scripts were removed in #3973 and #3987).
filegroup(
    name = "pending_target_files",
    srcs = [
        "//tools/ci:BUILD",
        "//tools/git:BUILD",
        "//tools/secret-scan:BUILD",
    ],
)

# The repo's hook files and the launchers, for the tests.
filegroup(
    name = "wiring",
    srcs = LAUNCHERS + [
        "//:.agents/hooks.json",
        "//:.claude/settings.json",
    ],
)

# The crate's own unit tests (the parser, the regex ports, JSON, paths).
rust_test(
    name = "agent_guard_lib_test",
    size = "small",
    crate = ":agent_guard_lib",
    data = [":pending_target_files"],
    edition = "2021",
)

# The decision table (400+ real commands, testdata/decision_table.json),
# redaction, scope, modes, hook I/O, the hook files' protection, the repo's
# real .claude/settings.json and .agents/hooks.json (which fail the test if
# agent-guard is unwired from either), and a real-git merge conflict for the
# in-progress checks. Calls the library directly.
rust_test(
    name = "agent_guard_test",
    size = "small",
    srcs = glob(["tests/**/*.rs"]),
    crate_root = "tests/main.rs",
    data = [
        "policy.json",
        "testdata/decision_table.json",
        ":wiring",
    ],
    edition = "2021",
    deps = [":agent_guard_lib"],
)

# The backstop against a temporary HOME (install, migration, rollback,
# uninstall, the agent checks) and --check against a throwaway checkout.
rust_test(
    name = "install_test",
    size = "small",
    args = [
        "--skip",
        "launcher_test::",
    ],
    crate = ":install",
    data = [
        "policy.json",
        ":wiring",
    ],
    edition = "2021",
)

# Each launcher (hook.sh, proposed-hook.sh while it exists) in a throwaway git
# checkout: origin/main's guard rather than a local edit, the working-copy and
# stale-build fallbacks, each program tried in turn, both agents' working
# folders; and the Rust launcher building the real src/ with the toolchain's
# rustc, then answering.
rust_test(
    name = "hook_test",
    size = "medium",
    args = ["launcher_test::"],
    crate = ":install",
    data = glob(["src/*.rs"]) + [
        "policy.json",
        ":wiring",
        "@rules_rust//rust/toolchain:current_rust_stdlib_files",
        "@rules_rust//rust/toolchain:current_rustc_files",
        "@rules_rust//rust/toolchain:current_rustc_lib_files",
    ],
    edition = "2021",
    env = {"AGENT_GUARD_RUSTC": "$(rootpath @rules_rust//rust/toolchain:current_rustc_files)"},
)
