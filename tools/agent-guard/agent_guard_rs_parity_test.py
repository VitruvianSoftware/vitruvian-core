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

"""agent_guard_rs (the Rust port) against agent_guard.py.

Two kinds of check:

1. Differential. A pristine copy of agent_guard.py and the binary decide the
   same inputs and must agree field for field: every row of
   agent_guard_test.py's TABLE (decision, category, message, scope, op, and
   the table's own expectation), each row under warn and off modes and from a
   worktree and from outside, variations of the rows (wrapped in bash -c,
   $(...), env, a cd), a seeded fuzz corpus of shell text through the parser
   and the decision, redaction, and whole hook payloads (stdout, exit code and
   the log line).

2. The Python guard's own tests, re-run with the binary in its place:
   agent_guard_test.py's classes, with agent_guard's evaluate, main, parser,
   redaction, policy loader, git probe and installer check replaced by calls
   into the binary.
"""

import importlib.util
import io
import json
import os
import random
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from typing import Any, Dict, List
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import agent_guard as g  # noqa: E402  (the module the original tests use)
import agent_guard_test as T  # noqa: E402


def _load_pristine():
    """A second, untouched copy of agent_guard.py: the reference to compare to."""
    spec = importlib.util.spec_from_file_location(
        "agent_guard_reference", os.path.join(HERE, "agent_guard.py")
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load agent_guard.py from %s" % HERE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


P = _load_pristine()


def _binary():
    path = os.environ.get("AGENT_GUARD_RS", "")
    for cand in (path, os.path.join(os.getcwd(), path)):
        if cand and os.path.isfile(cand):
            return os.path.abspath(cand)
    raise RuntimeError("agent_guard_rs not found (AGENT_GUARD_RS=%r)" % path)


BIN = _binary()


class Batch(object):
    """One long-lived `agent_guard_rs --batch`: a JSON request per line."""

    def __init__(self):
        self._lock = threading.Lock()
        self._proc = None

    def _start(self):
        return subprocess.Popen(
            [BIN, "--batch"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
            encoding="utf-8",
        )

    def __call__(self, **req):
        with self._lock:
            proc = self._proc
            if proc is None or proc.poll() is not None:
                proc = self._proc = self._start()
            if proc.stdin is None or proc.stdout is None:
                raise RuntimeError("agent_guard_rs --batch has no pipes")
            proc.stdin.write(json.dumps(req) + "\n")
            proc.stdin.flush()
            line = proc.stdout.readline()
        if not line:
            raise RuntimeError("agent_guard_rs --batch died on %r" % (req,))
        out = json.loads(line)
        if "panic" in out:
            # The Python guard raised here too, or this is a port bug; either
            # way the caller sees an exception, as it would from Python.
            raise RuntimeError("agent_guard_rs: %s" % out["panic"])
        return out


RUST = Batch()


# ---------------------------------------------------------------------------
# The binary behind agent_guard's functions.
# ---------------------------------------------------------------------------
def _state_json(st):
    return {
        "merge": bool(st.merge),
        "rebase": bool(st.rebase),
        "cherry_pick": bool(st.cherry_pick),
        "unmerged": list(st.unmerged),
        "primary": bool(st.primary),
    }


def _installer_override():
    ip = g.installer_problem
    if isinstance(ip, mock.NonCallableMock):  # a test patched it
        return ip.return_value
    return None


def rust_evaluate(command, cwd, modes=None, home=None, git_state=None, cwd_known=True):
    req = {
        "kind": "evaluate",
        "command": command,
        "cwd": cwd,
        "home": home,
        "modes": modes,
        "cwd_known": cwd_known,
        "git_state": _state_json(git_state(cwd)) if git_state is not None else None,
    }
    override = _installer_override()
    if override is not None:
        req["installer_problem"] = override
    d = RUST(**req)
    return g.Decision(d["decision"], d["category"], d["message"], d["scope"], d["op"])


def _commands(out, module):
    if out.get("error") == "parse":
        raise module.ParseError("unbalanced")
    if out.get("error") == "too_complex":
        raise module.TooComplex()
    cmds = []
    for c in out["commands"]:
        sc = module.SimpleCommand()
        sc.words = c["words"]
        sc.redirects = [tuple(r) for r in c["redirects"]]
        sc.heredocs = c["heredocs"]
        sc.herestrings = c["herestrings"]
        cmds.append(sc)
    return cmds


def rust_parse_script(text, depth=0, budget=None):
    return _commands(RUST(kind="parse", text=text), g)


def rust_fallback_split(text, budget=None):
    return _commands(RUST(kind="fallback_split", text=text), g)


def rust_strip_heredoc_bodies(text):
    return RUST(kind="strip_heredoc_bodies", text=text)["text"]


def rust_body_substitutions(body):
    return RUST(kind="body_substitutions", text=body)["subs"]


def rust_redact(text):
    return RUST(kind="redact", text=text)["text"]


def rust_redact_for_log(text):
    return RUST(kind="redact_for_log", text=text)["text"]


def rust_load_policy(path):
    out = RUST(kind="load_policy", path=path)
    if "crash" in out:
        raise AttributeError(out["crash"])
    return out["modes"]


def rust_probe_git_state(cwd):
    s = RUST(kind="probe_git_state", cwd=cwd)
    return g.GitState(
        merge=s["merge"],
        rebase=s["rebase"],
        cherry_pick=s["cherry_pick"],
        unmerged=s["unmerged"],
        primary=s["primary"],
    )


def rust_installer_problem(cwd, home):
    return RUST(kind="installer_problem", cwd=cwd, home=home)["text"]


def run_hook(stdin_text, env=None, cwd=None):
    """The binary as the hook: (exit code, stdout)."""
    r = subprocess.run(
        [BIN],
        input=stdin_text.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env if env is not None else dict(os.environ),
        cwd=cwd or os.getcwd(),
        timeout=30,
    )
    return r.returncode, r.stdout.decode("utf-8")


def rust_main(argv=None, stdin=None, stdout=None):
    stdin = stdin or sys.stdin
    stdout = stdout or sys.stdout
    if argv and argv[0] in ("--version", "-V"):
        r = subprocess.run([BIN] + list(argv), stdout=subprocess.PIPE, timeout=30)
        stdout.write(r.stdout.decode("utf-8"))
        return r.returncode
    rc, out = run_hook(stdin.read())
    stdout.write(out)
    return rc


SHIMS = {
    "evaluate": rust_evaluate,
    "main": rust_main,
    "parse_script": rust_parse_script,
    "fallback_split": rust_fallback_split,
    "strip_heredoc_bodies": rust_strip_heredoc_bodies,
    "body_substitutions": rust_body_substitutions,
    "redact": rust_redact,
    "redact_for_log": rust_redact_for_log,
    "load_policy": rust_load_policy,
    "probe_git_state": rust_probe_git_state,
    "installer_problem": rust_installer_problem,
}
for _name, _fn in SHIMS.items():
    setattr(g, _name, _fn)


# ---------------------------------------------------------------------------
# 1. Differential: the reference copy and the binary on the same inputs.
# ---------------------------------------------------------------------------
FIELDS = ("decision", "category", "message", "scope", "op")


def _fields(d):
    return tuple(getattr(d, f) for f in FIELDS)


def _ref_state(states, key):
    s = states[key]
    return P.GitState(
        merge=s.merge,
        rebase=s.rebase,
        cherry_pick=s.cherry_pick,
        unmerged=list(s.unmerged),
        primary=s.primary,
    )


class _Both(object):
    """Runs one command through the reference and the binary from a fixture."""

    def __init__(self, fx):
        self.fx = fx

    def ref(self, command, cwd, key, modes=None, cwd_known=True):
        P._scope_cache.clear()
        P._root_cache.clear()
        state = _ref_state(self.fx.states, key)
        with mock.patch.object(P, "installer_problem", return_value=""):
            return P.evaluate(
                command,
                cwd,
                modes=modes,
                home=self.fx.home,
                git_state=lambda _d: state,
                cwd_known=cwd_known,
            )

    def rust(self, command, cwd, key, modes=None, cwd_known=True):
        state = self.fx.states[key]
        return RUST(
            kind="evaluate",
            command=command,
            cwd=cwd,
            home=self.fx.home,
            modes=modes,
            cwd_known=cwd_known,
            git_state=_state_json(state),
            installer_problem="",
        )

    def compare(self, command, cwd, key, modes=None, cwd_known=True):
        a = _fields(self.ref(command, cwd, key, modes, cwd_known))
        b = self.rust(command, cwd, key, modes, cwd_known)
        b = tuple(b[f] for f in FIELDS)
        return a, b


def _short(s, n=160):
    s = repr(s)
    return s if len(s) <= n else s[:n] + "...(%d chars)" % len(s)


class DifferentialTableTest(unittest.TestCase):
    """Every TABLE row through both guards, compared field by field."""

    @classmethod
    def setUpClass(cls):
        cls.fx = T.Fixture()
        cls.both = _Both(cls.fx)

    @classmethod
    def tearDownClass(cls):
        cls.fx.close()

    def _run(self, rows, where="repo", modes=None, cwd_known=True, expect=True):
        failures = []
        for command, want, cat, key in rows:
            text = self.fx.fmt(command)
            if where == "repo":
                cwd = self.fx.out if key == "out" else self.fx.repo
            else:
                cwd = getattr(self.fx, where)
            a, b = self.both.compare(text, cwd, key, modes, cwd_known)
            if a != b:
                diff = [
                    "%s: py=%s rs=%s" % (f, _short(x), _short(y))
                    for f, x, y in zip(FIELDS, a, b)
                    if x != y
                ]
                failures.append(
                    "%s [%s]: %s" % (_short(command), key or "-", "; ".join(diff))
                )
            elif expect and (b[0], b[1]) != (want, cat):
                failures.append(
                    "%s [%s]: table wants %s/%s, both say %s/%s"
                    % (_short(command), key or "-", want, cat, b[0], b[1])
                )
        return failures

    def test_every_row_matches_the_python_guard(self):
        failures = self._run(T.TABLE)
        sys.stderr.write("\nparity: %d table rows compared\n" % len(T.TABLE))
        self.assertEqual(failures, [], "\n" + "\n".join(failures))
        self.assertGreaterEqual(len(T.TABLE), 400)

    def test_every_row_in_warn_and_off_mode(self):
        failures = []
        for mode in ("warn", "off"):
            modes = {c: mode for c in P.CATEGORIES}
            failures += [
                "%s: %s" % (mode, f)
                for f in self._run(T.TABLE, modes=modes, expect=False)
            ]
        self.assertEqual(failures, [], "\n" + "\n".join(failures))

    def test_every_row_from_a_worktree_outside_and_unknown(self):
        failures = []
        for where in ("wt", "out", "home"):
            failures += [
                "%s: %s" % (where, f)
                for f in self._run(T.TABLE, where=where, expect=False)
            ]
        failures += [
            "unknown: %s" % f for f in self._run(T.TABLE, cwd_known=False, expect=False)
        ]
        self.assertEqual(failures, [], "\n" + "\n".join(failures))

    def test_variations_of_every_row(self):
        rows = []
        for command, _w, _c, key in T.TABLE:
            if len(command) > 2000:
                continue
            q = command.replace("'", "'\\''")
            for shape in (
                "bash -c '%s'" % q,
                'echo "$(%s)"' % command,
                "env FOO=1 %s" % command,
                "cd {wt} && %s" % command,
                "cd {out}; %s" % command,
                "true && (%s) | cat" % command,
                "CLAUDECODE= %s" % command,
                "%s # trailing comment" % command,
            ):
                rows.append((shape, None, None, key))
        failures = self._run(rows, expect=False)
        sys.stderr.write("parity: %d row variations compared\n" % len(rows))
        self.assertEqual(failures, [], "\n" + "\n".join(failures))


# Pieces the fuzzer joins into shell text: real words, operators, quotes,
# substitutions, heredocs, redirections and the odd broken bit.
FUZZ_PIECES = [
    "git",
    "push",
    "commit",
    "-m",
    "x",
    "gh",
    "pr",
    "merge",
    "go",
    "test",
    "./...",
    "bazel",
    "run",
    "//tools/agent-guard:install",
    "--",
    "--check",
    "rm",
    "-rf",
    "~/.cache/bazel",
    "cd",
    "{out}",
    "{wt}",
    "{repo}",
    "{home}/.local/share/agent-guard/x",
    ".claude/settings.json",
    "tools/agent-guard/hook.sh",
    "python3",
    "-c",
    "\"open('.agents/hooks.json','w')\"",
    "env",
    "-u",
    "CLAUDECODE",
    "sudo",
    "timeout",
    "5",
    "xargs",
    "find",
    ".",
    "-exec",
    "{}",
    ";",
    "&&",
    "||",
    "|",
    ";",
    "&",
    "\n",
    "(",
    ")",
    "{",
    "}",
    "'",
    '"',
    "`",
    "$(",
    "$((",
    "))",
    "${",
    "<<",
    "<<-",
    "<<<",
    "EOF",
    "'EOF'",
    ">",
    ">>",
    "2>&1",
    "<(",
    "&>",
    "#",
    "\\",
    "\\\n",
    "$'a\\tb'",
    "kubectl",
    "apply",
    "-f",
    "helm",
    "upgrade",
    "pnpm",
    "install",
    "cargo",
    "build",
    "xcrun",
    "notarytool",
    "git -C",
    "--git-dir=/x/.git",
    "stash",
    "worktree",
    "add",
    "-b",
    "checkout",
    "fetch",
    "origin",
    "main:main",
    "+refs/heads/*:refs/remotes/o/*",
    "-c",
    "remote.origin.url=x",
    "api",
    "-X",
    "POST",
    "graphql",
    "-f",
    "query='mutation { x }'",
    "repos/o/r/pulls",
    "-R",
    "a/b",
    "https://github.com/VitruvianSoftware/vitruvian-core/pull/1",
    "cp",
    "x",
    ".claude/",
    "tee",
    "sed",
    "-i",
    "eval",
    "watch",
    "-n",
    "1",
    "mise",
    "exec",
    "uv",
    "run",
    "pytest",
    "\t",
    "  ",
    "é",
    "ı",
    "\u00a0",
]


def _fuzz_cases(seed, count):
    rnd = random.Random(seed)
    out = []
    for _ in range(count):
        n = rnd.randint(1, 14)
        parts = []
        for _ in range(n):
            parts.append(rnd.choice(FUZZ_PIECES))
            parts.append(rnd.choice((" ", " ", " ", "", "\n")))
        out.append("".join(parts))
    return out


class DifferentialFuzzTest(unittest.TestCase):
    """Seeded random shell text: the parser's output and the decision must match."""

    @classmethod
    def setUpClass(cls):
        cls.fx = T.Fixture()
        cls.both = _Both(cls.fx)
        cls.cases = [cls.fx.fmt(c) for c in _fuzz_cases(20261024, 3000)]

    @classmethod
    def tearDownClass(cls):
        cls.fx.close()

    def test_parser(self):
        failures = []
        for text in self.cases:
            try:
                ref = [
                    (c.words, c.redirects, c.heredocs, c.herestrings)
                    for c in P.parse_script(text)
                ]
            except P.ParseError:
                ref = "parse"
            except P.TooComplex:
                ref = "too_complex"
            out = RUST(kind="parse", text=text)
            got = out.get("error") or [
                (
                    c["words"],
                    [tuple(r) for r in c["redirects"]],
                    c["heredocs"],
                    c["herestrings"],
                )
                for c in out["commands"]
            ]
            if ref != got:
                failures.append(
                    "%s: py=%s rs=%s" % (_short(text), _short(ref), _short(got))
                )
            ref_fb = [c.words for c in P.fallback_split(text)]
            got_fb = [
                c["words"] for c in RUST(kind="fallback_split", text=text)["commands"]
            ]
            if ref_fb != got_fb:
                failures.append(
                    "fallback %s: py=%s rs=%s"
                    % (_short(text), _short(ref_fb), _short(got_fb))
                )
            if (
                P.strip_heredoc_bodies(text)
                != RUST(kind="strip_heredoc_bodies", text=text)["text"]
            ):
                failures.append("strip_heredoc_bodies %s" % _short(text))
            if (
                P.body_substitutions(text)
                != RUST(kind="body_substitutions", text=text)["subs"]
            ):
                failures.append("body_substitutions %s" % _short(text))
        sys.stderr.write(
            "\nparity: %d fuzz cases through the parser\n" % len(self.cases)
        )
        self.assertEqual(failures, [], "\n" + "\n".join(failures[:40]))

    def test_decisions(self):
        failures = []
        for i, text in enumerate(self.cases):
            key = ("", "merging", "worktree", "rebasing")[i % 4]
            cwd = (self.fx.repo, self.fx.wt, self.fx.out)[i % 3]
            a, b = self.both.compare(text, cwd, key)
            if a != b:
                diff = [
                    "%s: py=%s rs=%s" % (f, _short(x), _short(y))
                    for f, x, y in zip(FIELDS, a, b)
                    if x != y
                ]
                failures.append("%s: %s" % (_short(text), "; ".join(diff)))
        self.assertEqual(failures, [], "\n" + "\n".join(failures[:40]))


REDACTION_CORPUS = [
    "mysql -phunter2 db",  # gitleaks:allow
    "psql postgres://app:s3cr3t@db:5432/x",  # gitleaks:allow
    "curl -u admin:adm1npass https://x",  # gitleaks:allow
    "curl --user=admin:pw https://x",  # gitleaks:allow
    "curl -uroot:pw x",  # gitleaks:allow
    "gh secret set FOO --body s3cretvalue",
    "gh secret set FOO -b 'two words'",
    'gh secret set FOO --body="quoted value" -R x/y',
    "gh secret set X   -b\t'v'",
    "curl -H 'X-Api-Key: k3yvalue' https://x",  # gitleaks:allow
    "curl -H 'PRIVATE-TOKEN: glvalue123' x",  # gitleaks:allow
    "curl -H 'Authorization: Bearer sekrit-value-123' https://x",  # gitleaks:allow
    'curl -H "Authorization:   token abcdefgh12345" x',  # gitleaks:allow
    "AUTHORIZATION:x",
    "authorization          : y",
    "Cookie: a=b; c=d",
    "x-goog-api-key:\n v",
    "echo ghs_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123",  # gitleaks:allow
    "echo github_pat_11ABCDEFG0123456789_abcdefghijklmnop",  # gitleaks:allow
    "echo xoxb-1234567890-abcdefghij",  # gitleaks:allow
    "echo sk-ant-api03-abcdefghijklmnopqrstuvwxyz",  # gitleaks:allow
    "AKIAABCDEFGHIJKLMNOP",  # gitleaks:allow
    "AIzaSyA1234567890abcdefghijklmnopqrstuv",  # gitleaks:allow
    "glpat-abcdefghijklmnopqrstuvwxyz",  # gitleaks:allow
    "tool --password=hunter2",  # gitleaks:allow
    "tool --password hunter2",  # gitleaks:allow
    "tool --token\t\tx",
    "curl 'https://x/?token=abc123def'",
    "API_KEY=xyz789 ./run",
    "my.access-key=1 secret_thing=2 credentialsX=3",
    "git clone https://user:pa55word@github.com/x/y",  # gitleaks:allow
    "vault login --token s.abcdef",
    "git log -p 5",
    "git log -p -5",
    "patch -p1 < x.diff",
    "git apply -p2 x",
    "find . -print",
    "find . -printf %p",
    "find . -path ./x -prune",
    "-perm -pipe -plain -pretty -paginate -push -pull",
    "-p12 -p123 -p1a -p -p- -pé",
    "sudo -u james ls",
    "mkdir -p a/b",
    "gh secret list",
    "ssh -p 2222 host",
    "Basic dXNlcjpwYXNz",
    "bearer    abcdefgh",
    "BEARER\tabcdefg",
    "ſecret=x",
    "toKen=x",
    "\u212aEY",
    "x" * 1300 + " token=abc",
    "a" * 70 + "_token=x",
    "secret set " + "y" * 300 + " -b v",
    "--token=" + "z" * 1500,
]


class DifferentialRedactionTest(unittest.TestCase):
    def test_redaction_matches(self):
        rnd = random.Random(7)
        corpus = list(REDACTION_CORPUS)
        for _ in range(1500):
            corpus.append(
                "".join(
                    rnd.choice(
                        REDACTION_CORPUS + [" ", "=", ":", "-", "'", '"', "@", "/"]
                    )
                    for _ in range(rnd.randint(1, 5))
                )
            )
        failures = []
        for text in corpus:
            for fn in ("redact", "redact_for_log"):
                a = getattr(P, fn)(text)
                b = RUST(kind=fn, text=text)["text"]
                if a != b:
                    failures.append(
                        "%s %s: py=%s rs=%s" % (fn, _short(text), _short(a), _short(b))
                    )
        self.assertEqual(failures, [], "\n" + "\n".join(failures[:40]))


def _strip_ts(records):
    return [{k: v for k, v in r.items() if k != "ts"} for r in records]


class DifferentialHookTest(unittest.TestCase):
    """Whole payloads through both hooks: stdout, exit code and the log line."""

    def setUp(self):
        self.fx = T.Fixture()
        self.policy = os.path.join(self.fx.tmp, "policy.json")
        shutil.copy(P.default_policy_path(), self.policy)
        self.homes = {}
        settings = os.path.join(self.fx.home, ".claude", "settings.json")
        os.makedirs(os.path.dirname(settings))
        with open(settings, "w") as fh:
            json.dump(T.USER_SETTINGS, fh, indent=2)
        self.settings = settings

    def tearDown(self):
        self.fx.close()

    def _env(self):
        env = dict(os.environ)
        env.update(
            AGENT_GUARD_HOME=self.fx.home,
            AGENT_GUARD_POLICY=self.policy,
            AGENT_GUARD_SOURCE="origin/main:parity",
        )
        return env

    def _log(self):
        path = P.log_path(self.fx.home)
        if not os.path.exists(path):
            return []
        with open(path) as fh:
            return [json.loads(line) for line in fh]

    def _clear_log(self):
        path = P.log_path(self.fx.home)
        if os.path.exists(path):
            os.remove(path)

    def _ref(self, stdin_text):
        env = self._env()
        P._scope_cache.clear()
        P._root_cache.clear()
        out = io.StringIO()
        with mock.patch.dict(os.environ, env, clear=True):
            rc = P.main([], stdin=io.StringIO(stdin_text), stdout=out)
        return rc, out.getvalue()

    def payloads(self):
        fx = self.fx
        DC = P.DC
        p: List[Dict[str, Any]] = []
        for cmd in (
            "git push",
            "git status",
            "go vet ./...",
            "GH_TOKEN=ghs_abcdefghijklmnopqrstuvwxyz0123 git push",  # gitleaks:allow
            "echo " + "x" * 5000,
            "rm -rf ~/.cache/bazel",
            "true; " * 25000,
            "gh pr merge 1 -R someone/else",
            "cat > %s/.claude/settings.json" % fx.repo,
            "bazel run //tools/agent-guard:install -- --mode go=off",
        ):
            for cwd in (fx.repo, fx.out, ""):
                p.append(
                    {
                        "tool_name": "Bash",
                        "cwd": cwd,
                        "session_id": "s1",
                        "tool_input": {"command": cmd},
                    }
                )
            p.append(
                {
                    "toolCall": {
                        "name": "run_command",
                        "args": {"CommandLine": cmd, "Cwd": fx.repo},
                    },
                    "conversationId": "c1",
                }
            )
            p.append(
                {
                    "toolCall": {"name": "run_command", "args": {"CommandLine": cmd}},
                    "workspacePaths": [fx.out, fx.repo],
                }
            )
            p.append({"toolCall": {"name": "shell_exec", "args": {"command": cmd}}})
        p += [
            {
                "tool_name": "mcp__terminal__run_in_terminal",
                "cwd": fx.out,
                "tool_input": {"command": "git push", "cwd": fx.repo},
            },
            {
                "tool_name": "Monitor",
                "cwd": fx.repo,
                "tool_input": {"command": "pnpm test"},
            },
            {
                "tool_name": DC + "interact_with_process",
                "cwd": fx.repo,
                "tool_input": {"input": "git commit -m x"},
            },
            {
                "tool_name": "mcp__ccd_pr__set_auto_merge",
                "cwd": fx.out,
                "tool_input": {
                    "url": "https://github.com/VitruvianSoftware/vitruvian-core/pull/3",
                    "enabled": True,
                },
            },
            {
                "tool_name": "mcp__ccd_pr__set_auto_merge",
                "cwd": fx.repo,
                "tool_input": {"url": "x", "enabled": False},
            },
            {
                "tool_name": "mcp__kubernetes__kubectl_apply",
                "cwd": fx.repo,
                "tool_input": {"manifest": "é", "n": 1.5},
            },
            {
                "tool_name": "mcp__kubernetes__kubectl_generic",
                "cwd": fx.repo,
                "tool_input": {"command": "delete", "subCommand": "pod"},
            },
            {
                "tool_name": "mcp__kubernetes__kubectl_rollout",
                "cwd": fx.repo,
                "tool_input": {"subCommand": "status"},
            },
            {
                "tool_name": "mcp__Kubernetes_MCP_Server__install_helm_chart",
                "cwd": fx.repo,
                "tool_input": {},
            },
            {
                "tool_name": "Edit",
                "cwd": fx.repo,
                "tool_input": {"file_path": fx.repo + "/.claude/settings.json"},
            },
            {
                "tool_name": "Write",
                "cwd": fx.repo,
                "tool_input": {
                    "file_path": fx.home + "/.local/state/agent-guard/log.jsonl"
                },
            },
            {
                "tool_name": "Edit",
                "cwd": fx.out,
                "tool_input": {
                    "file_path": self.settings,
                    "old_string": "high",
                    "new_string": "low",
                },
            },
            {
                "tool_name": "Edit",
                "cwd": fx.out,
                "tool_input": {
                    "file_path": self.settings,
                    "old_string": "agent-guard-backstop",
                    "new_string": "x",
                },
            },
            {
                "tool_name": "Write",
                "cwd": fx.out,
                "tool_input": {"file_path": self.settings, "content": "{}"},
            },
            {
                "tool_name": "MultiEdit",
                "cwd": fx.out,
                "tool_input": {
                    "file_path": self.settings,
                    "edits": [
                        {"old_string": "x", "new_string": '"disableAllHooks": true'}
                    ],
                },
            },
            {
                "tool_name": DC + "move_file",
                "cwd": fx.out,
                "tool_input": {"source": fx.home + "/.claude", "destination": "/tmp/x"},
            },
            {
                "toolCall": {
                    "name": "manage_task",
                    "args": {"Action": "send_input", "Input": "git push"},
                }
            },
            {"toolCall": {"name": "manage_task", "args": {"Action": "status"}}},
            {
                "toolCall": {
                    "name": "git_commit",
                    "args": {"Message": "x", "toolAction": "a"},
                },
                "conversationId": "c",
            },
            {
                "toolCall": {
                    "name": "write_to_file",
                    "args": {"TargetFile": fx.repo + "/.agents/hooks.json"},
                }
            },
            {"tool_name": "Read", "cwd": fx.repo, "tool_input": {"file_path": "x"}},
            {
                "tool_name": "Bash",
                "cwd": fx.repo,
                "tool_input": {"command": ["git", "push"]},
            },
            {"tool_name": "Bash", "cwd": fx.repo, "tool_input": {"command": 5}},
            {
                "tool_name": "Bash",
                "cwd": fx.repo,
                "tool_input": {"command": "git -C $'a\\0b' add x"},
            },
        ]
        return [json.dumps(x) for x in p] + [
            "",
            "not json",
            "[]",
            '{"tool_name": "Bash", "x": NaN}',
        ]

    def test_payloads_match(self):
        failures = []
        payloads = self.payloads()
        for text in payloads:
            self._clear_log()
            ref = self._ref(text)
            ref_log = _strip_ts(self._log())
            self._clear_log()
            got = run_hook(text, env=self._env())
            got_log = _strip_ts(self._log())
            if ref != got or ref_log != got_log:
                failures.append(
                    "%s:\n  py=%s %s\n  rs=%s %s"
                    % (
                        _short(text),
                        _short(ref),
                        _short(ref_log, 400),
                        _short(got),
                        _short(got_log, 400),
                    )
                )
        sys.stderr.write("\nparity: %d hook payloads compared\n" % len(payloads))
        self.assertEqual(failures, [], "\n" + "\n".join(failures))

    def test_version(self):
        r = subprocess.run([BIN, "--version"], stdout=subprocess.PIPE)
        out = io.StringIO()
        P.main(["--version"], stdout=out)
        self.assertEqual(r.stdout.decode(), out.getvalue())


# ---------------------------------------------------------------------------
# 2. The Python guard's own tests, with the binary in its place.
# ---------------------------------------------------------------------------
class RustDecisionTableTest(T.DecisionTableTest):
    pass


class RustInstallerSourceTest(T.InstallerSourceTest):
    pass


class RustScopeTest(T.ScopeTest):
    pass


class RustModesTest(T.ModesTest):
    pass


class RustPerformanceTest(T.PerformanceTest):
    pass


class RustRedactionTest(T.RedactionTest):
    pass


class RustHookIOTest(T.HookIOTest):
    pass


class RustUserFileToolTest(T.UserFileToolTest):
    pass


class RustAntigravityHookTest(T.AntigravityHookTest):
    pass


class RustParserTest(T.ParserTest):
    pass


class RustRealGitStateTest(T.RealGitStateTest):
    pass


class ShimsAreInPlaceTest(unittest.TestCase):
    """The re-run classes above really reach the binary, not the Python guard."""

    def test_shims(self):
        for name, fn in SHIMS.items():
            self.assertIs(getattr(g, name), fn, name)
        self.assertIsNot(P.evaluate, g.evaluate)

    def test_a_shimmed_call_runs_the_binary(self):
        with tempfile.TemporaryDirectory() as home:
            d = g.evaluate(
                "git status", "/", home=home, git_state=lambda _d: g.GitState()
            )
        self.assertEqual(d.decision, "allow")
        with mock.patch.object(Batch, "__call__", side_effect=RuntimeError("binary")):
            with self.assertRaises(RuntimeError):
                g.evaluate("git status", "/")


if __name__ == "__main__":
    unittest.main(verbosity=2)
