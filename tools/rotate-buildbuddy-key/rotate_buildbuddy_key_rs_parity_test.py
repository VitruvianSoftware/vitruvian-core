#!/usr/bin/env python3
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
"""rotate-buildbuddy-key, the Rust port, against rotate.sh: same exit code,
stdout (every prompt included), stderr, and the same gh / open / sleep calls
-- with the key each `gh secret set` received on stdin -- on every case
below. The operator's answers come in on stdin.

    bazel test //tools/rotate-buildbuddy-key:rotate_buildbuddy_key_rs_parity_test

Then, for both, the property the tool exists for: the key never appears in
the output or on any command line, only on `gh secret set`'s stdin.
"""

import os
import subprocess
import sys
import tempfile

sys.path.insert(
    0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shell-compat")
)
from parity_harness import (  # noqa: E402
    Case,
    Harness,
    need_env,
    path_without,
    write,
    write_exec,
)

GH = r"""#!/usr/bin/env bash
printf 'gh %s\n' "$*" >>"$LOGDIR/calls.log"
case "$1 $2" in
  "auth status")
    echo "Logged in" >&2
    [ "${FAKE_AUTH_FAIL:-0}" = 1 ] && exit 1; exit 0 ;;
  "api user")
    [ "${FAKE_LOGIN_FAIL:-0}" = 1 ] && { printf 'partial\n\n'; echo "HTTP 401" >&2; exit 1; }
    echo octocat ;;
  "api repos/"*)
    [ "${FAKE_SECRET_MISSING:-0}" = 1 ] && { echo "HTTP 404" >&2; exit 1; }
    [ "$3" = --jq ] && echo "2026-10-01T00:00:00Z" || echo '{"name":"BUILDBUDDY_API_KEY"}' ;;
  "secret set")
    printf 'stdin[%s]\n' "$(cat)" >>"$LOGDIR/calls.log"
    echo "✓ Set secret $3"
    for p in ${FAKE_SET_FAIL_ON:-}; do case "$*" in *"$p"*) echo "HTTP 403" >&2; exit 1 ;; esac; done
    exit 0 ;;
  "run list")
    echo "listing" >&2
    [ -n "${FAKE_RUNID:-}" ] && printf '%s\n' "$FAKE_RUNID"
    exit 0 ;;
  "run rerun")
    [ "${FAKE_RERUN_FAIL:-0}" = 1 ] && exit 1; exit 0 ;;
  "run view")
    [ "${FAKE_VIEW_FAIL:-0}" = 1 ] && exit 1
    n=$(cat "$LOGDIR/view.n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" >"$LOGDIR/view.n"
    set -- ${FAKE_STATES:-in_progress/-}
    i=1; st="$1"
    for s; do [ "$i" -le "$n" ] && st="$s"; i=$((i + 1)); done
    printf '%s\n' "$st" ;;
esac
"""

OPEN = r"""#!/usr/bin/env bash
printf 'open %s\n' "$*" >>"$LOGDIR/calls.log"
[ "${FAKE_OPEN_FAIL:-0}" = 1 ] && { echo "no browser" >&2; exit 1; }
echo "opened"
"""

SLEEP = r"""#!/usr/bin/env bash
printf 'sleep %s\n' "$*" >>"$LOGDIR/calls.log"
[ "${FAKE_SLEEP_FAIL:-0}" = 1 ] && exit 130
exit 0
"""

GIT = r"""#!/usr/bin/env bash
printf 'git %s\n' "$*" >>"$LOGDIR/calls.log"
[ "${FAKE_GIT_FAIL:-0}" = 1 ] && { echo "fatal: not a git repository" >&2; exit 128; }
printf '%s\n' "$LOGDIR/gitroot"
"""

DEVYAML = "infrastructure/pulumi/platform/repo_config/Pulumi.dev.yaml"
CLEAN = "config:\n  # buildbuddyApiKey: comes from the environment\n  repo:x: y\n"
DIRTY = "config:\n  repo_config:buildbuddyApiKey:\n    secure: AAAbbb\n"


def fakes(open_=True, gh=True, devyaml=None, where="ws"):
    def setup(root):
        b = os.path.join(root, "bin")
        if gh:
            write_exec(os.path.join(b, "gh"), GH)
        if open_:
            write_exec(os.path.join(b, "open"), OPEN)
        write_exec(os.path.join(b, "sleep"), SLEEP)
        write_exec(os.path.join(b, "git"), GIT)
        if devyaml is not None:
            write(os.path.join(root, where, DEVYAML), devyaml)

    return setup


def env(**kw):
    e = {"BUILD_WORKSPACE_DIRECTORY": "{root}/ws", "LOGDIR": "{root}"}
    e.update(kw)
    return e


KEY = b"bb-NEW-KEY-0123456789"
HAPPY = b"\n" + KEY + b"\nn\n\n"  # (no open on PATH) pause, key, verify? no, pause


def main():
    h = Harness("rotate-buildbuddy-key", need_env("ROTATE_SH"), need_env("ROTATE_RS"))
    no_open = "{root}/bin:" + path_without("open")
    no_gh = "{root}/bin:" + path_without("gh")
    no_git = "{root}/bin:" + path_without("git")
    cases = [
        Case(
            "happy path, no `open`",
            env=env(PATH=no_open),
            stdin=HAPPY,
            setup=fakes(open_=False, devyaml=CLEAN),
        ),
        Case(
            "open the console: y; key with spaces around it",
            env=env(),
            stdin=b"y\n\n  " + KEY + b"  \nN\n\n",
            setup=fakes(),
        ),
        Case(
            "open: 'yes ', open fails",
            env=env(FAKE_OPEN_FAIL="1"),
            stdin=b" yes \n\n" + KEY + b"\nno\n\n",
            setup=fakes(),
        ),
        Case(
            "open: Yes is not yes",
            env=env(),
            stdin=b"Yes\n\n" + KEY + b"\n\n\n",
            setup=fakes(),
        ),
        Case(
            "end of input at the first pause",
            env=env(PATH=no_open),
            stdin=b"",
            setup=fakes(open_=False),
        ),
        Case("end of input at the open prompt", env=env(), stdin=b"y", setup=fakes()),
        Case(
            "empty key", env=env(PATH=no_open), stdin=b"\n\n", setup=fakes(open_=False)
        ),
        Case(
            "blank key",
            env=env(PATH=no_open),
            stdin=b"\n \t \n",
            setup=fakes(open_=False),
        ),
        Case(
            "key at end of input, no newline",
            env=env(PATH=no_open),
            stdin=b"\n" + KEY,
            setup=fakes(open_=False),
        ),
        Case(
            "key with a backslash",
            env=env(PATH=no_open),
            stdin=b"\nab\\cd\nn\n\n",
            setup=fakes(open_=False),
        ),
        Case(
            "end of input at the last pause",
            env=env(PATH=no_open),
            stdin=b"\n" + KEY + b"\nn\n",
            setup=fakes(open_=False),
        ),
        Case("gh missing", env=env(PATH=no_gh), stdin=HAPPY, setup=fakes(gh=False)),
        Case(
            "gh not authenticated",
            env=env(PATH=no_open, FAKE_AUTH_FAIL="1"),
            stdin=HAPPY,
            setup=fakes(open_=False),
        ),
        Case(
            "login lookup fails",
            env=env(PATH=no_open, FAKE_LOGIN_FAIL="1"),
            stdin=HAPPY,
            setup=fakes(open_=False),
        ),
        Case(
            "secret not there yet",
            env=env(PATH=no_open, FAKE_SECRET_MISSING="1"),
            stdin=HAPPY,
            setup=fakes(open_=False),
        ),
        Case(
            "key still committed",
            env=env(PATH=no_open),
            stdin=HAPPY,
            setup=fakes(open_=False, devyaml=DIRTY),
        ),
        Case(
            "committed key, no space before colon",
            env=env(PATH=no_open),
            stdin=HAPPY,
            setup=fakes(open_=False, devyaml="buildbuddyApiKey  :abc"),
        ),
        Case(
            "workspace from git",
            env=env(PATH=no_open, BUILD_WORKSPACE_DIRECTORY=None),
            stdin=HAPPY,
            setup=fakes(open_=False, devyaml=DIRTY, where="gitroot"),
        ),
        Case(
            "empty workspace var, git fails: pwd",
            env=env(PATH=no_open, BUILD_WORKSPACE_DIRECTORY="", FAKE_GIT_FAIL="1"),
            stdin=HAPPY,
            setup=fakes(open_=False, devyaml=DIRTY, where="."),
        ),
        Case(
            "no git at all: pwd",
            env=env(
                PATH="{root}/bin:" + path_without("git", "open"),
                BUILD_WORKSPACE_DIRECTORY=None,
            ),
            stdin=HAPPY,
            setup=lambda root: (
                fakes(open_=False, devyaml=CLEAN, where=".")(root),
                os.remove(os.path.join(root, "bin/git")),
            ),
        ),
        Case(
            "Actions set fails",
            env=env(PATH=no_open, FAKE_SET_FAIL_ON="--repo"),
            stdin=HAPPY,
            setup=fakes(open_=False),
        ),
        Case(
            "Dependabot set fails",
            env=env(PATH=no_open, FAKE_SET_FAIL_ON="dependabot"),
            stdin=HAPPY,
            setup=fakes(open_=False),
        ),
        Case(
            "verify: no run found",
            env=env(PATH=no_open),
            stdin=b"\n" + KEY + b"\ny\n\n",
            setup=fakes(open_=False),
        ),
        Case(
            "verify: green on the third poll",
            env=env(
                PATH=no_open,
                FAKE_RUNID="98765",
                FAKE_STATES="queued/- in_progress/- completed/success",
            ),
            stdin=b"\n" + KEY + b"\nYES\n\n",
            setup=fakes(open_=False),
        ),
        Case(
            "verify: red",
            env=env(
                PATH=no_open,
                FAKE_RUNID="98765",
                FAKE_STATES="in_progress/- completed/failure",
            ),
            stdin=b"\n" + KEY + b"\ny\n\n",
            setup=fakes(open_=False),
        ),
        Case(
            "verify: rerun refused, view always fails (40 polls)",
            env=env(
                PATH=no_open,
                FAKE_RUNID="98765",
                FAKE_RERUN_FAIL="1",
                FAKE_VIEW_FAIL="1",
            ),
            stdin=b"\n" + KEY + b"\ny\n\n",
            setup=fakes(open_=False),
        ),
        Case(
            "verify: never finishes",
            env=env(PATH=no_open, FAKE_RUNID="98765"),
            stdin=b"\n" + KEY + b"\ny\n\n",
            setup=fakes(open_=False),
        ),
        Case(
            "verify: sleep interrupted",
            env=env(PATH=no_open, FAKE_RUNID="98765", FAKE_SLEEP_FAIL="1"),
            stdin=b"\n" + KEY + b"\ny\n\n",
            setup=fakes(open_=False),
        ),
        Case(
            "verify: no sleep on PATH",
            env=env(
                PATH="{root}/bin:" + path_without("sleep", "open"), FAKE_RUNID="98765"
            ),
            stdin=b"\n" + KEY + b"\ny\n\n",
            setup=lambda root: (
                fakes(open_=False)(root),
                os.remove(os.path.join(root, "bin/sleep")),
            ),
        ),
    ]
    for c in cases:
        h.check(c)
    rc = h.finish()
    return rc or no_leak(h)


def no_leak(h):
    """The key reaches gh secret set's stdin -- twice -- and nowhere else."""
    bad = 0
    for label, cmd in (("sh", [h.bash, h.script]), ("rs", [h.binary])):
        root = tempfile.mkdtemp(prefix="leak.", dir=os.environ.get("TEST_TMPDIR"))
        for d in ("bin", "home", "tmp"):
            os.makedirs(os.path.join(root, d))
        fakes()(root)
        e = {
            "PATH": root + "/bin:" + h.base_path,
            "HOME": root + "/home",
            "TMPDIR": root + "/tmp",
            "LOGDIR": root,
            "BUILD_WORKSPACE_DIRECTORY": root + "/ws",
            "FAKE_RUNID": "1",
            "FAKE_STATES": "completed/success",
        }
        p = subprocess.run(
            cmd, input=b"n\n\n" + KEY + b"\ny\n\n", capture_output=True, env=e, cwd=root
        )
        with open(os.path.join(root, "calls.log"), "rb") as f:
            log = f.read()
        argv_lines = [ln for ln in log.splitlines() if not ln.startswith(b"stdin[")]
        problems = []
        if p.returncode != 0:
            problems.append("exit %d" % p.returncode)
        if KEY in p.stdout or KEY in p.stderr:
            problems.append("key in the output")
        if any(KEY in ln for ln in argv_lines):
            problems.append("key on a command line")
        if log.count(b"stdin[" + KEY + b"]") != 2:
            problems.append("key not delivered on stdin to both scopes")
        print(
            "  %s  no-leak check (%s)%s"
            % (
                "ok  " if not problems else "FAIL",
                label,
                (": " + ", ".join(problems)) if problems else "",
            )
        )
        bad += bool(problems)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
