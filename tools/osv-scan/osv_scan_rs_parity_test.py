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

"""osv-scan.sh and the Rust osv-scan, side by side.

Every scenario builds one scratch git repo (deterministic commit hashes), then
runs each implementation against an identical copy of it at the SAME path,
with the same environment and a fake osv-scanner whose behaviour is scripted
per call. For each run it records:

  * exit code, stdout and stderr (byte for byte);
  * every scanner invocation: argv (temp-file names normalised), working
    directory, GOWORK and GOFLAGS as the scanner saw them;
  * the working tree afterwards (every file's content, and `git status`);
  * what was left in TMPDIR (both must clean up after themselves).

and requires the two records to be identical. A handful of scenarios hit a
documented divergence (bash's own diagnostics, Python tracebacks); those
compare everything except stderr, and still require both to have written one.

Covers every scenario in osv-scan_test.sh plus the edge cases listed in BUILD.
The package.json "version-only bump" scenarios need jq for the shell side; if
jq is not on PATH they are skipped, loudly.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.getcwd()
RS = os.path.abspath(os.environ["OSV_SCAN_RS"])
SH = os.path.abspath(os.environ["OSV_SCAN_SH"])
WORK = tempfile.mkdtemp(prefix="osvpar-", dir=os.environ.get("TEST_TMPDIR"))

TOOLS = os.path.join(WORK, "tools")
os.makedirs(TOOLS)
for tool in ("git", "python3", "jq", "tar", "bash"):
    found = shutil.which(tool)
    if found:
        os.symlink(found, os.path.join(TOOLS, tool))
HAVE_JQ = os.path.exists(os.path.join(TOOLS, "jq"))
for need in ("git", "python3", "bash", "tar"):
    if not os.path.exists(os.path.join(TOOLS, need)):
        sys.exit(f"osv_scan_rs_parity_test: {need} is not on PATH")
BASH = os.path.join(TOOLS, "bash")

# The scripted scanner. FAKE_SPEC is a JSON list of per-call behaviours; the
# last one repeats. A call without --output-file (the human-readable re-run on
# findings) uses the spec's "rerun" entry when there is one.
FAKE = r"""#!/usr/bin/env python3
import json, os, sys
spec = json.load(open(os.environ["FAKE_SPEC"]))
state = os.environ["FAKE_STATE"]
argv = sys.argv[1:]
out = None
for i, a in enumerate(argv):
    if a == "--output-file" and i + 1 < len(argv):
        out = argv[i + 1]
with open(os.path.join(state, "calls"), "a") as f:
    f.write("x\n")
n = sum(1 for _ in open(os.path.join(state, "calls")))
if out is None and "rerun" in spec:
    beh = spec["rerun"]
else:
    calls = spec["calls"]
    beh = calls[min(n, len(calls)) - 1]
with open(os.path.join(state, "log"), "a") as f:
    f.write(json.dumps({"argv": argv, "cwd": os.getcwd(), "GOWORK": os.environ.get("GOWORK"),
                        "GOFLAGS": os.environ.get("GOFLAGS"), "PWD": os.environ.get("PWD")}) + "\n")
if beh.get("stdout"):
    sys.stdout.write(beh["stdout"])
if beh.get("stderr"):
    sys.stderr.write(beh["stderr"])
root = os.environ["FAKE_ROOT"]
for rel in beh.get("mutate", []):
    with open(os.path.join(root, rel), "a") as f:
        f.write("mutated\n")
if out is not None and "raw" in beh:
    with open(out, "w") as f:
        f.write(beh["raw"])
elif out is not None and "sources" in beh:
    results = [{"source": {"path": "/x/go.mod.%d" % (i % beh.get("distinct", 10**9)), "type": "lockfile"},
                "packages": []} for i in range(beh["sources"])]
    hit = False
    if beh.get("tree") and os.path.exists("findings.txt"):
        for line in open("findings.txt"):
            parts = line.rstrip("\n").split("|")
            if len(parts) != 5:
                continue
            path, eco, name, ver, vid = parts
            hit = True
            results.append({"source": {"path": path if path.startswith("/") else os.path.join(os.getcwd(), path)},
                            "packages": [{"package": {"name": name, "version": ver, "ecosystem": eco},
                                          "vulnerabilities": [{"id": vid}]}]})
    for extra in beh.get("extra", []):
        results.append(extra)
    json.dump({"results": results}, open(out, "w"))
    if beh.get("tree"):
        sys.exit(1 if hit else 0)
sys.exit(beh.get("rc", 0))
"""

TRANSIENT = "failed resolution for x/requirements.txt: rpc error: code = Unavailable desc = service unavailable\n"
ROSTER = "osv-scanner.toml has unused ignores:\n" + "".join(
    f" - GO-2026-TRAILING-NOISE-{i}\n" for i in range(1, 27)
)
A = "pnpm-lock.yaml|npm|axios|1.19.0|GHSA-aaaa"
B = "pnpm-lock.yaml|npm|next|16.3.3|GHSA-bbbb"
C = "pnpm-lock.yaml|npm|hono|4.13.0|GHSA-cccc"

GIT_ENV = {
    "GIT_AUTHOR_NAME": "t",
    "GIT_AUTHOR_EMAIL": "t@t",
    "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@t",
    "GIT_AUTHOR_DATE": "2026-01-01T00:00:00Z",
    "GIT_COMMITTER_DATE": "2026-01-01T00:00:00Z",
    "GIT_CONFIG_NOSYSTEM": "1",
}


def git(repo, *args, check=True):
    env = dict(os.environ, **GIT_ENV, HOME=WORK, PATH=TOOLS + ":/usr/bin:/bin")
    return subprocess.run(
        ["git", "-C", repo, *args], env=env, check=check, capture_output=True
    )


class Repo:
    """A recipe: commits applied in order to a fresh repo."""

    def __init__(self, git_repo=True):
        self.git_repo = git_repo
        self.steps = []  # ("commit", {path: content|None}) | ("dirty", {...}) | ("origin", branch)

    def commit(self, files):
        self.steps.append(("commit", files))
        return self

    def dirty(self, files):
        self.steps.append(("dirty", files))
        return self

    def origin(self, branch="main"):
        self.steps.append(("origin", branch))
        return self

    def build(self, path):
        os.makedirs(path)
        if not self.git_repo:
            for kind, files in self.steps:
                write_files(path, files)
            return
        git(path, "init", "-q", "-b", "main")
        write_files(path, {"tracked.txt": "tracked\n"})
        git(path, "add", "-A")
        git(path, "commit", "-qm", "init")
        for kind, arg in self.steps:
            if kind == "commit":
                write_files(path, arg)
                git(path, "add", "-A")
                git(path, "commit", "-qm", "step", "--allow-empty")
            elif kind == "dirty":
                write_files(path, arg)
            elif kind == "origin":
                bare = path + ".origin.git"
                subprocess.run(
                    ["git", "clone", "-q", "--bare", path, bare],
                    check=True,
                    capture_output=True,
                    env=dict(os.environ, **GIT_ENV, PATH=TOOLS + ":/usr/bin:/bin"),
                )
                git(path, "remote", "add", "origin", bare)


def write_files(root, files):
    for rel, content in files.items():
        p = os.path.join(root, rel)
        if content is None:
            if os.path.exists(p):
                os.remove(p)
            continue
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(content)


def head_rev(repo, rev="HEAD"):
    return git(repo, "rev-parse", rev).stdout.decode().strip()


def snapshot_tree(root):
    files = {}
    for dirpath, dirnames, filenames in os.walk(root):
        if ".git" in dirnames:
            dirnames.remove(".git")
        for fn in filenames:
            p = os.path.join(dirpath, fn)
            with open(p, "rb") as f:
                files[os.path.relpath(p, root)] = f.read()
    status = None
    if os.path.isdir(os.path.join(root, ".git")):
        status = git(root, "status", "--porcelain", check=False).stdout
    return files, status


TMPNAME = re.compile(r"/\S*?/tmp\.[A-Za-z0-9]+")


def run_one(impl, scen, template, rundir):
    root = os.path.join(rundir, "root")
    tmpdir = os.path.join(rundir, "tmp")
    state = os.path.join(rundir, "state")
    fakebin = os.path.join(rundir, "bin")
    for d in (root, tmpdir, state, fakebin, root + ".origin.git"):
        if os.path.lexists(d):
            shutil.rmtree(d)
    shutil.copytree(template, root, symlinks=True)
    if os.path.isdir(template + ".origin.git"):
        shutil.copytree(template + ".origin.git", root + ".origin.git", symlinks=True)
        git(root, "remote", "set-url", "origin", root + ".origin.git")
    os.makedirs(tmpdir)
    os.makedirs(state)
    os.makedirs(fakebin)
    open(os.path.join(state, "calls"), "w").close()
    spec_path = os.path.join(rundir, "spec.json")
    if scen.get("scanner") is not None:
        with open(spec_path, "w") as f:
            json.dump(scen["scanner"], f)
        with open(os.path.join(fakebin, "osv-scanner"), "w") as f:
            f.write(FAKE)
        os.chmod(os.path.join(fakebin, "osv-scanner"), 0o755)
    env = {
        "PATH": f"{fakebin}:{TOOLS}:/usr/bin:/bin",
        "HOME": WORK,
        "TMPDIR": tmpdir,
        "FAKE_SPEC": spec_path,
        "FAKE_STATE": state,
        "FAKE_ROOT": root,
        "OSV_RETRY_DELAY": "0",
        "BUILD_WORKSPACE_DIRECTORY": root,
        **GIT_ENV,
    }
    for k, v in scen.get("env", {}).items():
        if v is None:
            env.pop(k, None)
        else:
            env[k] = v.replace("@ROOT@", root).replace("@BASE@", scen.get("_base", ""))
    cwd = (
        os.path.join(root, scen.get("cwd", "")) if scen.get("cwd") is not None else root
    )
    if scen.get("cwd_outside"):
        cwd = rundir
    argv = [BASH, SH] if impl == "sh" else [RS]
    p = subprocess.run(
        argv,
        cwd=cwd,
        env=env,
        capture_output=True,
        stdin=subprocess.DEVNULL,
        timeout=240,
    )
    log = []
    lp = os.path.join(state, "log")
    if os.path.exists(lp):
        for line in open(lp):
            e = json.loads(line)
            e["argv"] = [TMPNAME.sub("<TMP>/tmp.X", a) for a in e["argv"]]
            for k in ("cwd", "PWD"):
                if e[k]:
                    e[k] = TMPNAME.sub("<TMP>/tmp.X", e[k])
            log.append(e)
    leftovers = sorted(os.listdir(tmpdir))
    tree = snapshot_tree(root)
    # Temp-directory names are random on both sides; everything else is not.
    tmpb = re.compile(rb"/\S*?/tmp\.[A-Za-z0-9]+")
    return {
        "rc": p.returncode,
        "stdout": tmpb.sub(b"<TMP>/tmp.X", p.stdout),
        "stderr": tmpb.sub(b"<TMP>/tmp.X", p.stderr),
        "scanner": log,
        "tmp_left": leftovers,
        "tree": tree,
    }


def S(**kw):
    """Scanner spec shorthand: a list of call behaviours."""
    return kw


def calls(*bs, rerun=None):
    d = {"calls": list(bs)}
    if rerun is not None:
        d["rerun"] = rerun
    return d


def ok_scan(n=60, rc=0, **kw):
    return dict(
        sources=n,
        rc=rc,
        stderr=kw.pop(
            "stderr",
            "SCANNER-STDERR-MARKER: rpc error: code = Unavailable desc = service unavailable\n"
            + ROSTER,
        ),
        **kw,
    )


def tree_scan(**kw):
    return dict(sources=60, tree=True, **kw)


SCENARIOS = []


def scenario(
    name,
    repo,
    scanner,
    env=None,
    needs_jq=False,
    compare_stderr=True,
    base_rev=None,
    **extra,
):
    SCENARIOS.append(
        dict(
            name=name,
            repo=repo,
            scanner=scanner,
            env=env or {},
            needs_jq=needs_jq,
            compare_stderr=compare_stderr,
            base_rev=base_rev,
            **extra,
        )
    )


def base_then(head_files, base_files=None):
    """A repo whose BASE_REV commit has base_files and HEAD adds head_files."""
    r = Repo()
    if base_files:
        r.commit(base_files)
    r.steps.append(("mark", None))
    r.commit(head_files)
    return r


# --- osv-scan_test.sh, scenario for scenario ---------------------------------------
scenario("clean scan, ample coverage", Repo(), calls(ok_scan(60, 0)))
scenario("under-covered scan fails despite rc 0", Repo(), calls(ok_scan(3, 0)))
scenario("advisories, no diff base: full-tree block", Repo(), calls(ok_scan(60, 1)))
scenario(
    "crash 127 with transient stderr: budget + fallback",
    Repo(),
    calls(ok_scan(60, 127)),
)
scenario(
    "scan mutates a tracked file", Repo(), calls(ok_scan(60, 0, mutate=["tracked.txt"]))
)
scenario(
    "transient failure retried then passes",
    Repo(),
    calls(dict(rc=127, stderr=TRANSIENT), dict(sources=60, rc=0)),
)
scenario(
    "OSV 404 client error retried then passes",
    Repo(),
    calls(
        dict(
            rc=127,
            stderr='error when retrieving vulns: client error: status="404 Not Found" body={"code":5,"message":"Vulnerability not found, but the following aliases were: CVE-2026-55553"}\n',
        ),
        dict(sources=60, rc=0),
    ),
)
scenario(
    "transient forever: fallback fails too",
    Repo(),
    calls(
        dict(
            rc=127,
            stderr="failed resolution: rpc error: code = Unavailable desc = service unavailable\n",
        )
    ),
)
scenario(
    "findings are not retried away",
    Repo(),
    calls(dict(sources=60, rc=1), dict(sources=60, rc=0)),
)
scenario(
    "non-network crash: one attempt",
    Repo(),
    calls(dict(rc=127, stderr="Error: unknown flag: --nope\n")),
)
scenario(
    "deps.dev outage degrades and passes",
    Repo(),
    calls(*[dict(rc=127, stderr=TRANSIENT)] * 5, dict(sources=60, rc=0)),
)
scenario(
    "degraded fallback still blocks on an advisory",
    Repo(),
    calls(*[dict(rc=127, stderr=TRANSIENT)] * 5, dict(sources=60, rc=1)),
)
scenario(
    "4a advisories, no manifest touched",
    base_then({"README.md": "doc\n"}),
    calls(ok_scan(60, 1)),
    base_rev="mark",
)
scenario(
    "4b advisories, go.mod changed",
    base_then({"go.mod": "module x\n"}),
    calls(ok_scan(60, 1)),
    base_rev="mark",
)
scenario(
    "4c advisories, osv-scanner.toml changed",
    base_then({"osv-scanner.toml": "# ignores\n"}),
    calls(ok_scan(60, 1)),
    base_rev="mark",
)
scenario(
    "4d advisories, no diff base",
    Repo().commit({"README.md": "doc\n"}),
    calls(ok_scan(60, 1)),
)
scenario(
    "4e advisories, unreadable base",
    Repo().commit({"README.md": "doc\n"}),
    calls(ok_scan(60, 1)),
    env={"BASE_REV": "0000000000000000000000000000000000000000"},
)
wide = {"go.mod": "module x\n"}
wide.update(
    {
        f"zz/padding-file-with-a-deliberately-long-name-{i}.txt": ""
        for i in range(1, 2001)
    }
)
scenario(
    "4f go.mod inside a >64KiB path list",
    base_then(wide),
    calls(ok_scan(60, 1)),
    base_rev="mark",
)


def added(name, base_findings, head_findings, **kw):
    r = Repo().commit({"findings.txt": base_findings})
    r.steps.append(("mark", None))
    r.commit({"findings.txt": head_findings, "go.mod": "module x\n"})
    scanner = kw.pop("scanner", calls(tree_scan()))
    scenario(name, r, scanner, base_rev="mark", **kw)


added("5a fix PR: 2 advisories -> 1", f"{A}\n{B}\n", f"{A}\n")
added("5b PR adding a new advisory", f"{A}\n", f"{A}\n{C}\n")
added("5c partial bump", f"{A}\n", "pnpm-lock.yaml|npm|axios|1.19.5|GHSA-aaaa\n")
added(
    "5d second vulnerable copy",
    f"{A}\n",
    f"{A}\npnpm-lock.yaml|npm|axios|0.9.0|GHSA-aaaa\n",
)
added(
    "5e same advisory in a new lockfile",
    f"{A}\n",
    f"{A}\napps/new/package-lock.json|npm|axios|1.19.0|GHSA-aaaa\n",
)
# 5f: the base scan crashes (the 3rd invocation: head scan, rerun, then base).
added(
    "5f base scan crash",
    f"{A}\n",
    f"{A}\n",
    scanner=calls(
        tree_scan(), tree_scan(), dict(rc=127, stderr="Error: boom\n"), rerun=dict(rc=1)
    ),
)
added(
    "5g base scan under-covered",
    f"{A}\n{B}\n",
    f"{A}\n",
    scanner=calls(tree_scan(), dict(sources=3, tree=True), rerun=dict(rc=1)),
)
added("5h comparison passes and leaves the repo untouched", f"{A}\n{B}\n", f"{A}\n")

# --- edge cases ----------------------------------------------------------------------
scenario(
    "GITHUB_ACTIONS: degraded pass annotates",
    Repo(),
    calls(*[dict(rc=127, stderr=TRANSIENT)] * 5, dict(sources=60, rc=0)),
    env={"GITHUB_ACTIONS": "true"},
)
scenario(
    "GITHUB_ACTIONS: pre-existing warning annotates",
    base_then({"README.md": "doc\n"}),
    calls(ok_scan(60, 1)),
    base_rev="mark",
    env={"GITHUB_ACTIONS": "true"},
)
scenario(
    "GITHUB_ACTIONS: clean pass has no annotation",
    Repo(),
    calls(ok_scan(60, 0)),
    env={"GITHUB_ACTIONS": "true"},
)
scenario("MIN_SOURCES boundary: 49", Repo(), calls(dict(sources=49)))
scenario("MIN_SOURCES boundary: 50", Repo(), calls(dict(sources=50)))
scenario(
    "60 results but 10 distinct sources", Repo(), calls(dict(sources=60, distinct=10))
)
for label, raw in [
    ("empty file", ""),
    ("invalid JSON", "{nope"),
    ("top-level list", "[]"),
    ("results null", '{"results": null}'),
    ("results {}", '{"results": {}}'),
    ("results empty string", '{"results": ""}'),
    ("results string", '{"results": "ab"}'),
    ("source is a string", '{"results": [{"source": "x"}]}'),
    ("path is a list", '{"results": [{"source": {"path": [1]}}]}'),
    ("no results key", '{"other": 1}'),
    (
        "1, 1.0 and true are one source",
        '{"results": [{"source": {"path": 1}}, {"source": {"path": 1.0}}, {"source": {"path": true}}, {"source": {}}, {}]}',
    ),
    (
        "duplicate keys: last wins",
        '{"results": [], "results": ['
        + ",".join('{"source":{"path":"p%d"}}' % i for i in range(55))
        + "]}",
    ),
    ("NaN literal", '{"results": [{"source": {"path": NaN}}]}'),
]:
    scenario(
        f"coverage JSON: {label}",
        Repo(),
        calls(dict(raw=raw, rc=0)),
        compare_stderr=True,
        py_divergent=(label == "NaN literal"),
    )
scenario(
    "rc 0 but no JSON written",
    Repo(),
    calls(dict(rc=0, stderr="No package sources found\n")),
)
scenario(
    "rc 128, no JSON, stderr without newline",
    Repo(),
    calls(dict(rc=128, stderr="line one\nNo package sources found")),
)
scenario("rc 128, no JSON, empty stderr", Repo(), calls(dict(rc=128)))
scenario(
    "rc 2, nothing matches the excerpt: silent exit 1 (set -e)",
    Repo(),
    calls(
        dict(
            sources=60,
            rc=2,
            stderr="".join(f"plain line {i}\n" for i in range(20)) + "\n\n",
        )
    ),
)
scenario("rc 2, empty stderr", Repo(), calls(dict(sources=60, rc=2)))
scenario(
    "rc 2, over 12 matching lines",
    Repo(),
    calls(
        dict(
            sources=60,
            rc=2,
            stderr="".join(f"ERROR number {i}\nok {i}\n" for i in range(20)),
        )
    ),
)
scenario(
    "rc 3, Panic and TIMEOUT match case-insensitively",
    Repo(),
    calls(
        dict(
            sources=60,
            rc=3,
            stderr="Panic: x\nall good\nread TIMEOUT\nno trailing newline FATAL",
        )
    ),
)
scenario(
    "rc 137 (signal-style) transient, fallback clean",
    Repo(),
    calls(dict(rc=137, stderr="Deadline Exceeded\n"), dict(sources=60, rc=0)),
    env={"OSV_MAX_ATTEMPTS": "1"},
)
scenario(
    "OSV_MAX_ATTEMPTS=2",
    Repo(),
    calls(dict(rc=127, stderr=TRANSIENT)),
    env={"OSV_MAX_ATTEMPTS": "2"},
)
scenario(
    "OSV_MAX_ATTEMPTS=0",
    Repo(),
    calls(dict(rc=127, stderr=TRANSIENT), dict(sources=60)),
    env={"OSV_MAX_ATTEMPTS": "0"},
)
scenario(
    "OSV_RETRY_DELAY=01 (octal doubling), 2 attempts",
    Repo(),
    calls(dict(rc=127, stderr="TLS handshake timeout\n")),
    env={"OSV_MAX_ATTEMPTS": "2", "OSV_RETRY_DELAY": "01"},
)
scenario(
    "OSV_RETRY_DELAY empty means 5 (but no retry needed)",
    Repo(),
    calls(dict(sources=60)),
    env={"OSV_RETRY_DELAY": ""},
)
scenario(
    "OSV_MAX_ATTEMPTS non-integer (bash diagnostic differs)",
    Repo(),
    calls(dict(rc=127, stderr=TRANSIENT), dict(sources=60)),
    env={"OSV_MAX_ATTEMPTS": "abc"},
    compare_stderr=False,
)
for word in [
    "connection refused",
    "no such host",
    "i/o timeout",
    "connection reset",
    "temporary failure in name resolution",
    'STATUS="404 x',
    "unAvailable",
]:
    scenario(
        f"transient marker: {word}",
        Repo(),
        calls(dict(rc=127, stderr=f"x {word} y\n"), dict(sources=60)),
    )
scenario(
    "transient marker split across lines does not match",
    Repo(),
    calls(dict(rc=127, stderr="rpc\nerror\n"), dict(sources=60)),
)
scenario(
    "mutation during the findings re-run",
    Repo(),
    calls(dict(sources=60, rc=1), rerun=dict(rc=1, mutate=["tracked.txt"])),
)
scenario(
    "mutation during the fallback scan only",
    Repo(),
    calls(
        *[dict(rc=127, stderr=TRANSIENT)] * 5, dict(sources=60, mutate=["tracked.txt"])
    ),
)
scenario(
    "scan creates an untracked file",
    Repo(),
    calls(dict(sources=60, mutate=["new-file.txt"])),
)
scenario(
    "pre-existing local edits are not the scan's",
    Repo().dirty({"tracked.txt": "edited\n", "z.txt": "u\n"}),
    calls(dict(sources=60)),
)
scenario(
    "pre-existing edit, scan touches another file",
    Repo().dirty({"tracked.txt": "edited\n"}),
    calls(dict(sources=60, mutate=["a.txt", "tracked.txt"])),
)
scenario(
    "osv-scanner.toml present: --config passed",
    Repo().commit({"osv-scanner.toml": "\n"}),
    calls(dict(sources=60)),
)
scenario("GOFLAGS already set", Repo(), calls(dict(sources=60)), env={"GOFLAGS": "-v"})
scenario("osv-scanner not on PATH", Repo(), None)
scenario(
    "BUILD_WORKSPACE_DIRECTORY unset: git toplevel from a subdirectory",
    Repo().commit({"sub/keep": "k\n"}),
    calls(dict(sources=60)),
    env={"BUILD_WORKSPACE_DIRECTORY": None},
    cwd="sub",
)
scenario(
    "BUILD_WORKSPACE_DIRECTORY unset outside git: pwd",
    Repo(git_repo=False),
    calls(dict(sources=60)),
    env={"BUILD_WORKSPACE_DIRECTORY": None},
)
scenario(
    "BUILD_WORKSPACE_DIRECTORY missing (bash cd diagnostic differs)",
    Repo(),
    calls(dict(sources=60)),
    env={"BUILD_WORKSPACE_DIRECTORY": "@ROOT@/nope"},
    compare_stderr=False,
)
scenario(
    "not a git repo, advisories found",
    Repo(git_repo=False),
    calls(dict(sources=60, rc=1)),
)
scenario(
    "BASE_REF set to a branch the origin has",
    base_then({"go.mod": "module y\n"}).origin(),
    calls(ok_scan(60, 1)),
    env={"BASE_REF": "main"},
)
scenario(
    "BASE_REF names no branch: fails closed, 'DOES touch'",
    Repo().commit({"README.md": "x\n"}).origin(),
    calls(ok_scan(60, 1)),
    env={"BASE_REF": "no-such-branch"},
)
scenario(
    "BASE_REF with docs-only change vs origin",
    Repo().origin().commit({"README.md": "x\n"}),
    calls(ok_scan(60, 1)),
    env={"BASE_REF": "main"},
)
scenario(
    "requirements-dev.txt changed blocks",
    base_then({"py/requirements-dev.txt": "x==1\n"}),
    calls(ok_scan(60, 1)),
    base_rev="mark",
)
scenario(
    "go.mod.bak changed does not count",
    base_then({"go.mod.bak": "x\n"}),
    calls(ok_scan(60, 1)),
    base_rev="mark",
)

PKG = '{"name":"x","version":"%s","dependencies":{"a":"^1"}}\n'
for label, base_files, head_files in [
    (
        "version-only bump",
        {"package.json": PKG % "1.0.0"},
        {"package.json": PKG % "1.0.1"},
    ),
    (
        "nested version-only bump",
        {"a/b/package.json": PKG % "1.0.0"},
        {"a/b/package.json": PKG % "2.0.0"},
    ),
    (
        "key order and whitespace only",
        {"package.json": PKG % "1"},
        {
            "package.json": '{ "dependencies": {"a": "^1"},\n  "version": "2", "name": "x" }'
        },
    ),
    (
        "dependency changed",
        {"package.json": PKG % "1"},
        {"package.json": PKG.replace("^1", "^2") % "1"},
    ),
    ("package.json added", {}, {"package.json": PKG % "1"}),
    (
        "number literal 1 -> 1.0",
        {"package.json": '{"n":1}'},
        {"package.json": '{"n":1.0}'},
    ),
    (
        "number literal 1E2 -> 1e+2",
        {"package.json": '{"n":1E2}'},
        {"package.json": '{"n":1e+2}'},
    ),
    (
        "NaN -> null",
        {"package.json": '{"n":NaN,"version":1}'},
        {"package.json": '{"n":null,"version":2}'},
    ),
    ("invalid on both sides", {"package.json": "{nope"}, {"package.json": "{nope "}),
    ("array on both sides", {"package.json": "[1]"}, {"package.json": "[1] "}),
    ("emptied on both sides", {"package.json": ""}, {"package.json": "\n"}),
    (
        "two values, version-only",
        {"package.json": '{"version":1}{"a":1}'},
        {"package.json": '{"version":2} {"a":1}'},
    ),
    (
        "composer.json version-only",
        {"composer.json": '{"version":"1","require":{}}'},
        {"composer.json": '{"version":"2","require":{}}'},
    ),
    (
        "version-only bump plus a lockfile",
        {"package.json": PKG % "1"},
        {"package.json": PKG % "2", "pnpm-lock.yaml": "x\n"},
    ),
    (
        "duplicate key resolves the same",
        {"package.json": '{"a":1,"a":2}'},
        {"package.json": '{"a":2}'},
    ),
]:
    scenario(
        f"jq: {label}",
        base_then(head_files, base_files),
        calls(ok_scan(60, 1)),
        base_rev="mark",
        needs_jq=True,
    )

TREE_SCAN = calls(tree_scan())
added(
    "advisory path outside the root stays absolute",
    f"{A}\n",
    f"/elsewhere/lock|npm|axios|1.19.0|GHSA-aaaa\n{A}\n",
)
added(
    "tab in a package name (awk field split)",
    f"{A}\n",
    f"{A}\npnpm-lock.yaml|npm|we\tird|1|GHSA-tab\n",
)
added(
    "many added, sorted output",
    f"{A}\n",
    "".join(f"l{i % 3}|npm|p{i}|{i}.0|GHSA-{9 - i}\n" for i in range(8)),
)
added(
    "same advisory, versions sorted and joined",
    "",
    "p|npm|x|2.0|G\np|npm|x|10.0|G\np|npm|x|1.0|G\n",
)
added(
    "removed everything: 2 -> 0 findings yet rc 1 (head has none)",
    f"{A}\n{B}\n",
    "",
    scanner=calls(dict(sources=60, rc=1, tree=False), rerun=dict(rc=1)),
)


def odd_result(extra):
    return calls(dict(sources=60, rc=1, extra=extra), rerun=dict(rc=1))


r_odd = Repo().commit({"x": "1\n"})
r_odd.steps.append(("mark", None))
r_odd.commit({"go.mod": "m\n"})
for label, extra, divergent in [
    (
        "vulnerabilities null",
        [
            {
                "source": {"path": "/p"},
                "packages": [{"package": {"name": "n"}, "vulnerabilities": None}],
            }
        ],
        False,
    ),
    (
        "vulnerabilities {}",
        [{"source": {"path": "/p"}, "packages": [{"vulnerabilities": {}}]}],
        False,
    ),
    (
        "vulnerabilities string",
        [{"source": {"path": "/p"}, "packages": [{"vulnerabilities": "ab"}]}],
        False,
    ),
    (
        "vulnerabilities number",
        [{"source": {"path": "/p"}, "packages": [{"vulnerabilities": 3}]}],
        False,
    ),
    ("packages null", [{"source": {"path": "/p"}, "packages": None}], False),
    (
        "path missing (realpath of cwd)",
        [
            {
                "packages": [
                    {
                        "package": {"name": "n", "version": "1"},
                        "vulnerabilities": [{"id": "G"}],
                    }
                ]
            }
        ],
        False,
    ),
    ("path is a number", [{"source": {"path": 5}, "packages": []}], False),
    (
        "relative path",
        [
            {
                "source": {"path": "rel/lock"},
                "packages": [
                    {
                        "package": {"name": "n", "version": "1"},
                        "vulnerabilities": [{"id": "G"}],
                    }
                ],
            }
        ],
        False,
    ),
    (
        "missing id, ecosystem and version",
        [
            {
                "source": {"path": "/p"},
                "packages": [{"package": {"name": "n"}, "vulnerabilities": [{}]}],
            }
        ],
        False,
    ),
    (
        "numeric version (join raises; traceback differs)",
        [
            {
                "source": {"path": "/p"},
                "packages": [
                    {
                        "package": {"name": "n", "version": 1},
                        "vulnerabilities": [{"id": "G"}],
                    }
                ],
            }
        ],
        True,
    ),
    (
        "true and 1 collapse as a version",
        [
            {
                "source": {"path": "/p"},
                "packages": [
                    {
                        "package": {"name": "n", "version": "a"},
                        "vulnerabilities": [{"id": "G"}],
                    },
                    {
                        "package": {"name": "n", "version": "a"},
                        "vulnerabilities": [{"id": "G"}],
                    },
                ],
            }
        ],
        False,
    ),
    (
        "package not a dict",
        [
            {
                "source": {"path": "/p"},
                "packages": [{"package": "s", "vulnerabilities": [{"id": "G"}]}],
            }
        ],
        False,
    ),
    (
        "unicode names",
        [
            {
                "source": {"path": "/p"},
                "packages": [
                    {
                        "package": {"name": "é中", "version": "µ"},
                        "vulnerabilities": [{"id": "G X"}],
                    }
                ],
            }
        ],
        False,
    ),
]:
    scenario(
        f"advisory JSON: {label}",
        r_odd,
        odd_result(extra),
        base_rev="mark",
        compare_stderr=not divergent,
    )


def materialise(scen, path):
    repo = scen["repo"]
    marks = [i for i, s in enumerate(repo.steps) if s[0] == "mark"]
    real = Repo(repo.git_repo)
    real.steps = [s for s in repo.steps if s[0] != "mark"]
    real.build(path)
    if scen["base_rev"] == "mark" and repo.git_repo:
        # Commits after the mark: count them to find the base.
        after = sum(1 for s in repo.steps[marks[0] :] if s[0] == "commit")
        scen["env"].setdefault("BASE_REV", "@BASE@")
        scen["_base"] = head_rev(path, f"HEAD~{after}")


def main():
    failures = []
    skipped = 0
    ran = 0
    for i, scen in enumerate(SCENARIOS):
        if scen["needs_jq"] and not HAVE_JQ:
            skipped += 1
            continue
        sdir = os.path.join(WORK, f"s{i}")
        template = os.path.join(sdir, "template")
        os.makedirs(sdir)
        materialise(scen, template)
        rundir = os.path.join(sdir, "run")
        os.makedirs(rundir)
        got = {impl: run_one(impl, scen, template, rundir) for impl in ("sh", "rs")}
        ran += 1
        keys = ["rc", "stdout", "scanner", "tmp_left", "tree"]
        if scen["compare_stderr"] and not scen.get("py_divergent"):
            keys.append("stderr")
        diffs = [k for k in keys if got["sh"][k] != got["rs"][k]]
        if not scen["compare_stderr"] and bool(got["sh"]["stderr"]) != bool(
            got["rs"]["stderr"]
        ):
            diffs.append("stderr (presence)")
        if diffs:
            failures.append(scen["name"])
            print(f"FAIL  {scen['name']}: differs in {', '.join(diffs)}")
            for k in diffs:
                k = k.split(" ")[0]
                print(f"   sh {k}: {got['sh'][k]!r}"[:3000])
                print(f"   rs {k}: {got['rs'][k]!r}"[:3000])
        else:
            print(f"ok    {scen['name']} (rc={got['sh']['rc']})")
        shutil.rmtree(sdir, ignore_errors=True)
    print()
    if skipped:
        print(
            f"SKIPPED {skipped} jq scenario(s): jq is not on PATH, so the shell side cannot run them."
        )
    if failures:
        print(f"FAILED {len(failures)} of {ran} scenarios")
        sys.exit(1)
    print(f"ALL {ran} scenarios identical")


if __name__ == "__main__":
    try:
        main()
    finally:
        shutil.rmtree(WORK, ignore_errors=True)
