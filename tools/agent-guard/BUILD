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
hook.sh, which runs the guard as it is on origin/main. A thin per-user
backstop covers sessions started outside the repo.

  bazel run //tools/agent-guard:install                  # install the backstop (once)
  bazel run //tools/agent-guard:install -- --check       # wiring, backstop and launcher OK?

See README.md.
"""

# Hand-written: gazelle's Python extension would otherwise generate its own
# targets beside these, and the folder name has a hyphen, so it cannot be a
# package: everything imports by path.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_library", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

exports_files([
    "agent_guard.py",
    "hook.sh",
    "policy.json",
])

# The guard on its own. Not how it runs in practice (hook.sh runs origin/main's
# copy on the machine's python3), but handy for trying a payload:
#   echo '{"tool_name":"Bash","cwd":"'$PWD'","tool_input":{"command":"git push"}}' | bazel run //tools/agent-guard
py_binary(
    name = "agent-guard",
    srcs = ["agent_guard.py"],
    data = ["policy.json"],
    imports = ["."],
    main = "agent_guard.py",
)

# Installs the per-user backstop (entries running the main checkout's hook.sh),
# migrating the old copied install; --check, --dry-run, --uninstall.
py_binary(
    name = "install",
    srcs = [
        "agent_guard.py",
        "install.py",
    ],
    data = ["policy.json"],
    imports = ["."],
    main = "install.py",
)

# The repo's hook files and the launcher, for the tests.
filegroup(
    name = "wiring",
    srcs = [
        "hook.sh",
        "//:.agents/hooks.json",
        "//:.claude/settings.json",
    ],
)

py_library(
    name = "testlib",
    testonly = True,
    srcs = ["testlib.py"],
    data = [
        "agent_guard.py",
        "policy.json",
        ":wiring",
    ],
    imports = ["."],
)

# The decision table (400+ real commands), redaction, scope, modes, hook I/O,
# the hook files' protection, and a real-git merge conflict for the
# in-progress checks.
py_test(
    name = "agent_guard_test",
    size = "small",
    srcs = [
        "agent_guard.py",
        "agent_guard_test.py",
    ],
    data = ["policy.json"],
    imports = ["."],
    main = "agent_guard_test.py",
)

# hook.sh in a throwaway git checkout: origin/main's guard rather than a local
# edit, the working-copy fallbacks, the python fallback, both agents' working
# folders; and the repo's real .claude/settings.json and .agents/hooks.json,
# which fail the test if agent-guard is unwired from either.
py_test(
    name = "hook_test",
    size = "small",
    srcs = [
        "agent_guard.py",
        "hook_test.py",
        "install.py",
    ],
    imports = ["."],
    main = "hook_test.py",
    deps = [":testlib"],
)

# The backstop against a temporary HOME (install, migration, rollback,
# uninstall) and --check against a throwaway checkout.
py_test(
    name = "install_test",
    size = "small",
    srcs = [
        "agent_guard.py",
        "install.py",
        "install_test.py",
    ],
    imports = ["."],
    main = "install_test.py",
    deps = [":testlib"],
)

# --- The Rust port -----------------------------------------------------------
# agent_guard.py stays the guard hook.sh runs; agent_guard_rs is a compiled
# port that must decide exactly as it does. The parity test below holds it to
# that by running agent_guard_test.py's own decision table and hook tests
# against the binary.
rust_library(
    name = "agent_guard_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "agent_guard",
    crate_root = "src/lib.rs",
    edition = "2021",
    # Optimised in every build mode: speed is why this port exists, and an
    # unoptimised build is slower than the Python guard on megabyte commands.
    rustc_flags = ["-Copt-level=3"],
    deps = ["@crates//:serde_json"],
)

# The hook, as the Python one: payload on stdin, answer on stdout.
#   echo '{"tool_name":"Bash","cwd":"'$PWD'","tool_input":{"command":"git push"}}' | bazel run //tools/agent-guard:agent_guard_rs
rust_binary(
    name = "agent_guard_rs",
    srcs = ["src/main.rs"],
    data = ["policy.json"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":agent_guard_lib"],
)

# The crate's own unit tests (the parser, the regex ports, JSON, paths).
rust_test(
    name = "agent_guard_lib_test",
    size = "small",
    crate = ":agent_guard_lib",
    edition = "2021",
)

# agent_guard_rs against agent_guard.py: every row of agent_guard_test.py's
# TABLE through both, compared field by field (decision, category, message,
# scope, op), then agent_guard_test.py's own test classes (table, scope,
# modes, installer source, redaction, parser, hook I/O, Antigravity, user
# files, performance, real git state) re-run with the binary in the Python
# guard's place.
py_test(
    name = "agent_guard_rs_parity_test",
    size = "small",
    srcs = [
        "agent_guard.py",
        "agent_guard_rs_parity_test.py",
        "agent_guard_test.py",
    ],
    data = [
        "policy.json",
        ":agent_guard_rs",
    ],
    env = {"AGENT_GUARD_RS": "$(rootpath :agent_guard_rs)"},
    imports = ["."],
    main = "agent_guard_rs_parity_test.py",
)
