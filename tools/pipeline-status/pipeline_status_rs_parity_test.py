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

"""pipeline-status.sh and its Rust port, side by side.

The script reads JSON with jq when it has it and with python3 when it does
not; the port follows the jq branch. Every case runs three ways:

  sh/jq   the script with the pinned hermetic jq (and python3) on PATH
  sh/py   the script with python3 and no jq
  rust    the binary

and the binary must match sh/jq exactly: exit code, stdout, stderr and the
gh calls it makes. It must match sh/py too wherever the script's own two
branches agree. Where jq itself fails on a value (a top-level number, say),
the error wording is jq's and version-bound, so those cases compare exit
code, stdout and calls only.

Two layers: `evaluate_runs_json` (the script's function, sourced, against
the port's probe) over a few thousand runs answers, and both programs end to
end against a mock gh in scratch git repositories.
"""

import concurrent.futures
import json
import os
import random
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

HOST_TOOLS = [
    "bash",
    "sh",
    "git",
    "cat",
    "env",
    "head",
    "tail",
    "grep",
    "cut",
    "date",
    "sleep",
    "mkdir",
    "rm",
    "mktemp",
    "dirname",
    "basename",
    "tr",
    "sed",
    "expr",
    "uname",
    "ls",
    "od",
    "printf",
    "xcrun",
]

MOCK_GH = r"""#!/bin/sh
d="$MOCK_DIR"
{ printf 'gh'; for a in "$@"; do printf '\037%s' "$a"; done; printf '\036\n'; } >> "$d/calls.log"
case "$*" in
  "api repos/"*"/actions/runs"*) key=runs ;;
  "api repos/"*"/pulls"*) key=pulls ;;
  "pr view "*"mergeCommit -q"*) key=merge ;;
  "pr view "*"headRefOid"*) key=head ;;
  "pr view "*) key=view ;;
  "pr checks "*) key=checks ;;
  "pr list "*) key=list ;;
  "run view "*) key=runlog ;;
  *) key=other ;;
esac
n=$(cat "$d/$key.count" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$d/$key.count"
i=$n
while [ "$i" -gt 1 ] && [ ! -e "$d/$key.$i.out" ]; do i=$((i - 1)); done
if [ ! -e "$d/$key.$i.out" ]; then exit 1; fi
cat "$d/$key.$i.out"
[ -e "$d/$key.$i.err" ] && cat "$d/$key.$i.err" >&2
exit "$(cat "$d/$key.$i.rc" 2>/dev/null || echo 0)"
"""


def runfile(env_name):
    path = os.environ[env_name]
    if path.startswith("external/"):
        path = "../" + path[len("external/") :]
    return os.path.abspath(path)


def write_exec(path, text):
    with open(path, "w") as f:
        f.write(text)
    os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


class World:
    """Shim directories every run shares: host tools without jq or python3,
    a python3 wrapper for the hermetic interpreter, and the hermetic jq."""

    def __init__(self, root):
        self.root = root
        self.tools = os.path.join(root, "tools")
        self.py = os.path.join(root, "py")
        self.jq = os.path.join(root, "jq")
        for d in (self.tools, self.py, self.jq):
            os.makedirs(d)
        host_path = os.environ.get("PATH", "") + ":/usr/bin:/bin"
        for tool in HOST_TOOLS:
            found = shutil.which(tool, path=host_path)
            if found:
                os.symlink(found, os.path.join(self.tools, tool))
        write_exec(
            os.path.join(self.py, "python3"),
            '#!/bin/sh\nexec "%s" -I "$@"\n' % sys.executable,
        )
        os.symlink(runfile("JQ_BIN"), os.path.join(self.jq, "jq"))
        self.home = os.path.join(root, "home")
        os.makedirs(self.home)

    def path(self, mode, mock_bin):
        dirs = [mock_bin] if mock_bin else []
        if mode == "jq":
            dirs.append(self.jq)
        dirs += [self.py, self.tools]
        return ":".join(dirs)

    def env(self, mode, mock_bin, mock_dir, extra=None):
        env = {
            "PATH": self.path(mode, mock_bin),
            "HOME": self.home,
            "GIT_CONFIG_NOSYSTEM": "1",
            "TZ": "UTC",
        }
        if mock_dir:
            env["MOCK_DIR"] = mock_dir
        for k, v in (extra or {}).items():
            if v is None:
                env.pop(k, None)
            else:
                env[k] = v
        return env


def git(repo, *args):
    subprocess.run(["git", "-C", repo, *args], check=True, capture_output=True)


def scratch_repo(parent):
    repo = tempfile.mkdtemp(dir=parent)
    git(repo, "init", "-q", "-b", "main")
    git(repo, "config", "user.email", "t@t")
    git(repo, "config", "user.name", "t")
    for i, msg in enumerate(["base", "feat: something (#77)", "fix: other (#78)"]):
        with open(os.path.join(repo, "f.txt"), "w") as f:
            f.write(str(i))
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", msg)
    git(repo, "update-ref", "refs/remotes/origin/main", "refs/heads/main")
    return repo


def gh_responses(mock_dir, responses):
    """responses: {key: [(stdout, rc), ...]}"""
    for key, seq in responses.items():
        for i, (out, rc) in enumerate(seq, 1):
            with open(os.path.join(mock_dir, "%s.%d.out" % (key, i)), "w") as f:
                f.write(out)
            with open(os.path.join(mock_dir, "%s.%d.rc" % (key, i)), "w") as f:
                f.write(str(rc))


# --- runs answers ------------------------------------------------------------

STATUSES = [
    "completed",
    "in_progress",
    "queued",
    "pending",
    "waiting",
    "requested",
    "COMPLETED",
]
CONCLUSIONS = [
    "success",
    "failure",
    "timed_out",
    "startup_failure",
    "skipped",
    "neutral",
    "cancelled",
    "action_required",
    "stale",
    None,
    "FAILURE",
]
NAMES = [
    "CI",
    "delivery",
    "lint",
    "presubmit",
    "release-please",
    "na|me",
    "é ✓ ⏳",
    "pipe|and:colon",
    "tab\there",
]
ODD = [None, True, False, 0, 1, -1, 2.5, "", "7", [1, "a"], {"k": "v", "a": None}]
MISSING = object()


def real_run(rng, wid, name, run_id):
    status = rng.choice(STATUSES[:4]) if rng.random() < 0.3 else "completed"
    conclusion = None if status != "completed" else rng.choice(CONCLUSIONS[:8])
    return {
        "id": run_id,
        "name": name,
        "workflow_id": wid,
        "head_sha": "0123456789abcdef0123456789abcdef01234567",
        "status": status,
        "conclusion": conclusion,
        "html_url": "https://github.com/VitruvianSoftware/vitruvian-core/actions/runs/%d"
        % run_id,
        "event": "push",
    }


def realistic_answer(rng):
    runs = []
    workflows = rng.sample(range(100, 140), rng.randint(1, 8))
    for wid in workflows:
        name = rng.choice(NAMES[:5]) + str(wid)
        for _ in range(rng.choice([1, 1, 1, 2, 3])):
            runs.append(real_run(rng, wid, name, rng.randint(1000, 99999)))
    rng.shuffle(runs)
    return json.dumps(
        {"total_count": len(runs), "workflow_runs": runs},
        separators=(",", ":") if rng.random() < 0.7 else (", ", ": "),
    )


def odd_value(rng, choices):
    if rng.random() < 0.2:
        return rng.choice(ODD)
    return rng.choice(choices)


def odd_run(rng):
    if rng.random() < 0.04:
        return rng.choice([None, 1, "s", [], True])
    run = {}
    fields = {
        "id": lambda: odd_value(rng, [1, 2, 3, 10, 10, 2.5]),
        "workflow_id": lambda: odd_value(rng, [1, 2, 3, 1.0]),
        "name": lambda: odd_value(rng, NAMES),
        "status": lambda: odd_value(rng, STATUSES),
        "conclusion": lambda: odd_value(rng, CONCLUSIONS),
        "html_url": lambda: odd_value(rng, ["https://x/runs/1", "u2"]),
    }
    keys = list(fields)
    rng.shuffle(keys)
    for key in keys:
        if rng.random() < 0.85:
            run[key] = fields[key]()
    if rng.random() < 0.1:
        k = rng.choice(keys)
        run[k] = fields[k]()  # appears again later: jq keeps the last value
        items = list(run.items())
        return (
            "{"
            + ",".join(json.dumps(a) + ":" + json.dumps(b) for a, b in items)
            + ","
            + json.dumps(k)
            + ":"
            + json.dumps(fields[k]())
            + "}"
        )
    return run


def dump_run(run):
    return run if isinstance(run, str) else json.dumps(run)


def odd_answer(rng):
    runs = (
        "[" + ",".join(dump_run(odd_run(rng)) for _ in range(rng.randint(0, 9))) + "]"
    )
    shape = rng.random()
    if shape < 0.75:
        return '{"total_count":3,"workflow_runs":%s}' % runs
    if shape < 0.8:
        return '{"workflow_runs":{"a":%s}}' % dump_run(odd_run(rng))
    if shape < 0.85:
        return (
            '{"message":"Not Found","status":"404"}\n{"total_count":0,"workflow_runs":%s}'
            % runs
        )
    if shape < 0.9:
        return '{"workflow_runs":%s}\n{"workflow_runs":%s}' % (runs, runs)
    return rng.choice(
        [
            "",
            " ",
            "null",
            "5",
            '"str"',
            "[]",
            "[1]",
            "true",
            '{"workflow_runs":null}',
            '{"workflow_runs":"x"}',
            '{"workflow_runs":5}',
            "{",
            '{"workflow_runs":[{"name":"a"',
            "not json",
            '{"a":1} trailing',
            '{"workflow_runs":[]}garbage',
        ]
    )


def answers():
    rng = random.Random(20261025)
    fixed = [
        '{"total_count":0,"workflow_runs":[]}',
        '{"total_count":2,"workflow_runs":[{"name":"CI","status":"completed","conclusion":"success"},'
        '{"name":"delivery","status":"completed","conclusion":"skipped"}]}',
        '{"workflow_runs":[{"name":"CI","status":"completed","conclusion":"success"},'
        '{"name":"delivery","status":"in_progress","conclusion":null}]}',
        '{"workflow_runs":[{"name":"CI","status":"completed","conclusion":"failure"},'
        '{"name":"delivery","status":"in_progress","conclusion":null}]}',
        # A rerun: the newest run of a workflow decides.
        '{"workflow_runs":[{"id":2,"workflow_id":7,"name":"CI","conclusion":"success"},'
        '{"id":1,"workflow_id":7,"name":"CI","conclusion":"failure","html_url":"u"}]}',
        # workflow_id 0 / false / "" — where jq's // and python's `or` differ.
        '{"workflow_runs":[{"workflow_id":0,"name":"a","conclusion":"success"},'
        '{"workflow_id":false,"name":"a","conclusion":"failure"}]}',
        '{"workflow_runs":[{"name":"","conclusion":"failure"}]}',
        '{"workflow_runs":[{"name":"CI","status":"queued"}]}',
    ]
    out = list(fixed)
    out += [realistic_answer(rng) for _ in range(900)]
    out += [odd_answer(rng) for _ in range(2100)]
    return out


# --- running -------------------------------------------------------------------


def run(cmd, env, cwd):
    p = subprocess.run(cmd, env=env, cwd=cwd, capture_output=True, timeout=120)
    return p.returncode, p.stdout, p.stderr


def calls(mock_dir):
    path = os.path.join(mock_dir, "calls.log")
    if not os.path.exists(path):
        return b""
    with open(path, "rb") as f:
        return f.read()


class Parity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.world = World(cls.tmp)
        cls.sh = runfile("PIPELINE_STATUS_SH")
        cls.rs = runfile("PIPELINE_STATUS_RS")
        cls.probe = runfile("PIPELINE_STATUS_RS_PROBE")
        jq = os.path.join(cls.world.jq, "jq")
        version = subprocess.run([jq, "--version"], capture_output=True, text=True)
        assert version.returncode == 0, version
        print("hermetic jq runs:", version.stdout.strip())
        # bash 3.2 answers `return ""` with 255, bash 5 with 2 (see evaluate.rs).
        p = subprocess.run(
            ["bash", "-c", 'f(){ return ""; }; f 2>/dev/null; echo $?'],
            capture_output=True,
            text=True,
            env=cls.world.env("py", None, None),
        )
        cls.empty_return = int(p.stdout.strip())
        print('this bash answers return "" with', cls.empty_return)
        cls.pool = concurrent.futures.ThreadPoolExecutor(
            max_workers=os.cpu_count() or 4
        )

    @classmethod
    def tearDownClass(cls):
        cls.pool.shutdown()
        shutil.rmtree(cls.tmp, ignore_errors=True)

    # -- evaluate_runs_json -----------------------------------------------------

    def evaluate(self, impl, mode, json_text):
        env = self.world.env(mode, None, None)
        if impl == "rs":
            cmd = [self.probe, "evaluate-runs-json", json_text]
        else:
            cmd = [
                "bash",
                "-c",
                'source "$1"; evaluate_runs_json "$2"',
                "_",
                self.sh,
                json_text,
            ]
        return run(cmd, env, self.tmp)

    def compare(self, label, rs, sh_jq, sh_py, jq_errors, stats, host_bound=False):
        """Hold rs to sh_jq, and to sh_py where the script's branches agree."""
        problems = []
        if host_bound:
            stats["host-bound"] += 1
            return problems
        if jq_errors:
            stats["jq-error"] += 1
            if (rs[0], rs[1]) != (sh_jq[0], sh_jq[1]):
                problems.append(
                    "%s: rc/stdout differ from sh/jq\n rs=%r\n sh=%r"
                    % (label, rs[:2], sh_jq[:2])
                )
        elif rs != sh_jq:
            problems.append(
                "%s: differs from sh/jq\n rs=%r\n sh=%r" % (label, rs, sh_jq)
            )
        else:
            stats["exact"] += 1
        if sh_py is not None:
            if sh_py == sh_jq:
                stats["branches-agree"] += 1
                if rs != sh_py and not jq_errors:
                    problems.append(
                        "%s: differs from sh/py where branches agree" % label
                    )
            else:
                stats["branches-differ"] += 1
        return problems

    def test_evaluate_runs_json(self):
        corpus = answers()

        def one(i, text):
            rs = self.evaluate("rs", "jq", text)
            sh_jq = self.evaluate("sh", "jq", text)
            sh_py = self.evaluate("sh", "py", text)
            return i, text, rs, sh_jq, sh_py

        stats = {
            "exact": 0,
            "jq-error": 0,
            "branches-agree": 0,
            "branches-differ": 0,
            "host-bound": 0,
        }
        problems = []
        results = self.pool.map(lambda a: one(*a), enumerate(corpus))
        for i, text, rs, sh_jq, sh_py in results:
            jq_errors = b"jq: " in sh_jq[2] or rs[0] == 255
            host_bound = rs[0] == 255 and self.empty_return != 255
            problems += self.compare(
                "answer %d %r" % (i, text[:120]),
                rs,
                sh_jq,
                sh_py,
                jq_errors,
                stats,
                host_bound,
            )
        print("evaluate_runs_json:", len(corpus), "answers", stats)
        self.assertEqual(problems, [], "\n".join(problems[:20]))
        self.assertGreater(stats["exact"], 2000)
        # The harness can see a difference: the script's own two branches
        # disagree on some of these answers.
        self.assertGreater(stats["branches-differ"], 50)
        self.assertGreater(stats["branches-agree"], 1000)

    # -- end to end ---------------------------------------------------------------

    def program(self, impl, mode, args, cwd, gh, env_extra=None, gh_present=True):
        mock_dir = tempfile.mkdtemp(dir=self.tmp)
        mock_bin = os.path.join(mock_dir, "bin")
        os.makedirs(mock_bin)
        if gh_present:
            write_exec(os.path.join(mock_bin, "gh"), MOCK_GH)
        gh_responses(mock_dir, gh)
        env = self.world.env(mode, mock_bin, mock_dir, env_extra)
        cmd = ([self.rs] if impl == "rs" else ["bash", self.sh]) + list(args)
        rc, out, err = run(cmd, env, cwd)
        # The one bash diagnostic the port repeats names the program.
        err = err.replace(self.sh.encode(), b"PROG").replace(self.rs.encode(), b"PROG")
        return rc, out, err, calls(mock_dir)

    def scenarios(self):
        repo = scratch_repo(self.tmp)
        head = subprocess.run(
            ["git", "-C", repo, "rev-parse", "HEAD"], capture_output=True, text=True
        ).stdout.strip()
        not_repo = tempfile.mkdtemp(dir=self.tmp)
        green = '{"total_count":1,"workflow_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}'
        red = (
            '{"workflow_runs":[{"name":"CI","status":"completed","conclusion":"failure","html_url":"u1"},'
            '{"name":"D","status":"queued","conclusion":null,"html_url":"u2"}]}'
        )
        flight = '{"workflow_runs":[{"name":"D","status":"queued","conclusion":null,"html_url":"u2"}]}'
        bws = {"BUILD_WORKSPACE_DIRECTORY": repo}
        out = []
        targets = [
            "",
            "HEAD",
            head,
            head[:8],
            "main",
            "HEAD~1",
            "nosuch",
            "77",
            "#77",
            "78",
            "#",
            "##77",
            "12a",
            "-x",
            "a b",
            "origin/main",
            "999",
        ]
        for t in targets:
            args = [t] if t != "" else []
            out.append(("target %r" % t, args, repo, {"runs": [(green, 0)]}, bws))
            out.append(("target %r red" % t, args, repo, {"runs": [(red, 0)]}, bws))
        for merge in [("abc123def", 0), ("", 0), ("", 1), ("partial", 1)]:
            for head_ref in [("feedface", 0), ("", 0), ("", 1)]:
                gh = {"merge": [merge], "head": [head_ref], "runs": [(flight, 0)]}
                out.append(
                    (
                        "pr 77 merge=%r head=%r" % (merge, head_ref),
                        ["77"],
                        repo,
                        gh,
                        bws,
                    )
                )
                out.append(
                    ("pr 5 merge=%r head=%r" % (merge, head_ref), ["#5"], repo, gh, bws)
                )
        for runs in [
            (green, 1),
            ('{"message":"Not Found"}', 1),
            ("", 0),
            ("", 1),
            (red, 0),
            (flight, 0),
            ('{"workflow_runs":[1]}', 0),
            ("5", 0),
        ]:
            out.append(("runs %r" % (runs,), [head], repo, {"runs": [runs]}, bws))
        for extra in [
            {"PIPELINE_REPO": "o/r"},
            {"PIPELINE_REPO": ""},
            {"BUILD_WORKSPACE_DIRECTORY": ""},
            {"BUILD_WORKSPACE_DIRECTORY": None},
            {"BUILD_WORKSPACE_DIRECTORY": os.path.join(self.tmp, "missing")},
            {"BUILD_WORKSPACE_DIRECTORY": os.path.join(repo, "f.txt")},
        ]:
            out.append(
                ("env %r" % extra, ["HEAD"], repo, {"runs": [(green, 0)]}, extra)
            )
            out.append(
                (
                    "env %r outside a repo" % extra,
                    ["HEAD"],
                    not_repo,
                    {"runs": [(green, 0)]},
                    extra,
                )
            )
        out.append(
            (
                "outside a repo, sha",
                ["abc"],
                not_repo,
                {"runs": [(red, 0)]},
                {"BUILD_WORKSPACE_DIRECTORY": None},
            )
        )
        rng = random.Random(7)
        for i, text in enumerate(rng.sample(answers(), 250)):
            out.append(("answer %d" % i, [head], repo, {"runs": [(text, 0)]}, bws))
        return out

    def test_programs_end_to_end(self):
        stats = {
            "exact": 0,
            "jq-error": 0,
            "branches-agree": 0,
            "branches-differ": 0,
            "host-bound": 0,
        }
        problems = []
        cases = self.scenarios()
        cases.append(("no gh on PATH", ["HEAD"], cases[0][2], {}, cases[0][4], False))

        def one(case):
            label, args, cwd, gh, extra = case[:5]
            present = case[5] if len(case) > 5 else True
            rs = self.program("rs", "jq", args, cwd, gh, extra, present)
            sh_jq = self.program("sh", "jq", args, cwd, gh, extra, present)
            sh_py = self.program("sh", "py", args, cwd, gh, extra, present)
            return label, rs, sh_jq, sh_py

        for label, rs, sh_jq, sh_py in self.pool.map(one, cases):
            jq_errors = b"jq: " in sh_jq[2]
            host_bound = (
                self.empty_return != 255
                and b"No workflow runs found" in rs[1]
                and b"No workflow runs found" not in sh_jq[1]
            )
            problems += self.compare(
                label, rs, sh_jq, sh_py, jq_errors, stats, host_bound
            )
        print("end to end:", len(cases), "scenarios", stats)
        self.assertEqual(problems, [], "\n".join(problems[:20]))
        self.assertGreater(stats["exact"] + stats["host-bound"], 300)


if __name__ == "__main__":
    unittest.main(verbosity=2)
