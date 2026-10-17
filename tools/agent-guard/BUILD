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

"""agent-guard: a Claude Code hook that keeps agents' repo and dev operations on Bazel targets.

  bazel run //tools/agent-guard:install [-- --dry-run | --check | --uninstall | --mode CATEGORY=MODE]

See README.md.
"""

# Hand-written: gazelle's Python extension would otherwise generate its own
# targets beside these, and the folder name has a hyphen, so it cannot be a
# package: everything imports by path.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_test")

exports_files([
    "agent_guard.py",
    "policy.json",
])

# The hook itself. Not how it runs in practice (the installed copy runs on the
# system python3), but handy for trying a payload:
#   echo '{"tool_name":"Bash","cwd":"'$PWD'","tool_input":{"command":"git push"}}' | bazel run //tools/agent-guard
py_binary(
    name = "agent-guard",
    srcs = ["agent_guard.py"],
    data = ["policy.json"],
    imports = ["."],
    main = "agent_guard.py",
)

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

# The decision table (400+ real commands), redaction, scope, modes, hook I/O,
# and a real-git merge conflict for the in-progress checks.
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

# The installer against a temporary HOME: merge, the two entries, idempotence,
# dry run, uninstall, modes, self-test and rollback, and its refusals.
py_test(
    name = "install_test",
    # Each case runs the real installer and its self-test: ~10 s locally.
    size = "medium",
    srcs = [
        "agent_guard.py",
        "install.py",
        "install_test.py",
    ],
    data = ["policy.json"],
    imports = ["."],
    main = "install_test.py",
)
