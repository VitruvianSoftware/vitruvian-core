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

"""Does each agent's GitHub App have exactly the permissions the code says?

    bazel run //tools/agent-app:permission-drift     # reads as your gh login
    python3 tools/agent-app/permission_drift.py      # the same, with no Bazel

WHY THIS EXISTS. GitHub has no API to change an App's permissions. It is a
by-hand change in the web UI: the App owner saves it (with a sudo prompt), then
the org accepts it on the installation page. Nothing recorded what the result
was meant to be, so a permission added for one task, or one that never got
accepted, was invisible. tools/agent-app/permissions.tsv is that record; this
fails when GitHub says otherwise. It is a drift guard, not a provisioner.

For every App in agents.tsv it compares three sets:

  declared   permissions.tsv
  granted    what the org ACCEPTED: the installation's permissions, from
             GET /orgs/{org}/installations
  requested  what the App's settings ASK for: GET /apps/{slug}

  ok         all three are the same.
  PENDING    the App asks for something the org has not accepted yet, and
             the code already declares it: someone has to click accept.
  DRIFT      the code and GitHub disagree, on either side.
  MISSING    the App in agents.tsv is not installed on the org (or the
             installation id points at a different App, or it is suspended).
  UNLISTED   a vitruvian-*-agent App is installed that agents.tsv does not know.
  NOT CHECKED GitHub could not be read for this App. Never a pass.

Reading the org's installations needs org Administration read: an org owner's
gh login, or in CI the vitruviansoftware-pulumi App's token
(.github/workflows/agent-app-permissions.yaml). Any installation token can read
/apps/{slug}. The token is GH_TOKEN, else GITHUB_TOKEN, else `gh auth token`.
Standard library only.

Exit: 0 every App matches · 1 drift, a pending request, or an App missing or
      unlisted · 2 GitHub could not be read, or a file here is wrong
"""

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

API = os.environ.get("GITHUB_API_URL", "https://api.github.com")
ORG = "VitruvianSoftware"
LEVELS = ("read", "write", "admin")
# The slug every agent App is created with (agent-app.sh's cmd_env builds the
# same name). Used only to spot an agent App that agents.tsv does not list.
AGENT_SLUG = re.compile(r"^vitruvian-[a-z0-9-]+-agent$")

OK, PENDING, DRIFT, MISSING, UNLISTED, UNREAD = (
    "ok",
    "PENDING",
    "DRIFT",
    "MISSING",
    "UNLISTED",
    "NOT CHECKED",
)


class ReadError(Exception):
    """GitHub did not give a usable answer. Always fails the check."""


class FileError(Exception):
    """agents.tsv or permissions.tsv is malformed. Always fails the check."""


# --------------------------------------------------------------------------
# The two committed files.
# --------------------------------------------------------------------------


def _rows(path):
    try:
        with open(path, encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    except OSError as err:
        raise FileError(f"cannot read {path}: {err}") from err
    for number, line in enumerate(lines, 1):
        if line.strip() and not line.startswith("#"):
            yield number, line.split("\t")


def load_agents(path):
    """agents.tsv -> [(agent, app_id, installation_id)], in file order."""
    agents = []
    for number, cols in _rows(path):
        if len(cols) < 3 or not all(c.strip() for c in cols[:3]):
            raise FileError(f"{path}:{number}: want agent, app_id, installation_id")
        name, app_id, inst_id = (c.strip() for c in cols[:3])
        if not (app_id.isdigit() and inst_id.isdigit()):
            raise FileError(
                f"{path}:{number}: app_id and installation_id must be numbers"
            )
        agents.append((name, int(app_id), int(inst_id)))
    if not agents:
        raise FileError(f"{path}: no agents listed")
    return agents


def load_declared(path, agents):
    """permissions.tsv -> {agent: {permission: level}}, checked against agents."""
    known = {name for name, _, _ in agents}
    declared = {}
    for number, cols in _rows(path):
        if len(cols) != 3:
            raise FileError(f"{path}:{number}: want agent, permission, level")
        name, perm, level = (c.strip() for c in cols)
        if name not in known:
            raise FileError(f"{path}:{number}: '{name}' is not in agents.tsv")
        if level not in LEVELS:
            raise FileError(
                f"{path}:{number}: level '{level}' is not one of {', '.join(LEVELS)}"
            )
        perms = declared.setdefault(name, {})
        if perm in perms:
            raise FileError(f"{path}:{number}: {name} declares {perm} twice")
        perms[perm] = level
    undeclared = [name for name, _, _ in agents if name not in declared]
    if undeclared:
        raise FileError(f"{path}: no permissions declared for {', '.join(undeclared)}")
    return declared


# --------------------------------------------------------------------------
# GitHub.
# --------------------------------------------------------------------------


class GitHub:
    """GET-only REST client. Every failure is a ReadError, never a default."""

    def __init__(self, token, api=API):
        self.token = token
        self.api = api.rstrip("/")

    def get(self, path_or_url):
        """-> (parsed JSON body, URL of the next page or None)."""
        url = path_or_url if "://" in path_or_url else self.api + path_or_url
        request = urllib.request.Request(
            url,
            headers={
                # A header, never the URL: a token in a URL ends up in logs.
                "Authorization": f"Bearer {self.token}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": "VitruvianSoftware/vitruvian-core agent-app permission-drift",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                raw = response.read()
                link = response.headers.get("Link", "")
        except urllib.error.HTTPError as err:
            raise ReadError(
                f"GET {_short(url)}: HTTP {err.code} {_message(err)}"
            ) from err
        except (urllib.error.URLError, OSError) as err:
            raise ReadError(
                f"GET {_short(url)}: {getattr(err, 'reason', err)}"
            ) from err
        try:
            body = json.loads(raw)
        except ValueError as err:
            raise ReadError(f"GET {_short(url)}: the answer is not JSON") from err
        return body, _next_link(link)


def _short(url):
    """https://api.github.com/apps/x -> /apps/x, for messages."""
    return "/" + url.split("://", 1)[-1].split("/", 1)[-1]


def _message(err):
    try:
        return json.loads(err.read()).get("message", "")
    except Exception:  # noqa: BLE001 -- the status code is the fact; this is colour
        return ""


def _next_link(header):
    for part in header.split(","):
        match = re.match(r'\s*<([^>]+)>\s*;\s*rel="next"', part)
        if match:
            return match.group(1)
    return None


def org_installations(github, org):
    """Every App installation on the org, following pages, counted."""
    url = f"/orgs/{org}/installations?per_page=100"
    found, total = [], None
    while url:
        body, url = github.get(url)
        if not isinstance(body, dict) or not isinstance(
            body.get("installations"), list
        ):
            raise ReadError(
                f"/orgs/{org}/installations: no installations list in the answer"
            )
        total = body.get("total_count")
        found.extend(body["installations"])
    # A page we failed to follow would silently drop Apps, and a dropped App
    # reads as MISSING, or worse, an unlisted one is never seen.
    if total != len(found):
        raise ReadError(
            f"/orgs/{org}/installations: GitHub counts {total} installations but {len(found)} were read"
        )
    return found


def requested_permissions(github, slug, app_id):
    body, _ = github.get(f"/apps/{slug}")
    if not isinstance(body, dict) or not isinstance(body.get("permissions"), dict):
        raise ReadError(f"/apps/{slug}: no permissions in the answer")
    if body.get("id") != app_id:
        raise ReadError(
            f"/apps/{slug}: answer is App {body.get('id')}, expected {app_id}"
        )
    return body["permissions"]


# --------------------------------------------------------------------------
# Judging.
# --------------------------------------------------------------------------


# Who says what, in the words the report uses.
CODE = ("permissions.tsv", "declares")
GRANT = ("GitHub", "grants")
ASK = ("the App's settings", "ask for")


def differences(a, a_set, b, b_set):
    """One plain sentence for every permission where two sets disagree."""
    (a_name, a_verb), (b_name, b_verb) = a, b
    lines = []
    for perm in sorted(set(a_set) | set(b_set)):
        x, y = a_set.get(perm), b_set.get(perm)
        if x == y:
            continue
        if x is None:
            lines.append(f"{b_name} {b_verb} {perm}={y}; {a_name} does not")
        elif y is None:
            lines.append(f"{a_name} {a_verb} {perm}={x}; {b_name} does not")
        else:
            lines.append(f"{perm}: {a_name} {a_verb} {x}, {b_name} {b_verb} {y}")
    return lines


def judge(app_id, inst_id, declared, inst, requested, org):
    """-> (state, [detail lines]) for one App.

    requested is the App's requested permissions, or a ReadError if they could
    not be read. inst is the org installation with this id, or None.
    """
    if inst is None:
        return MISSING, [
            f"installation {inst_id} is not on {org}: the App is not installed, or agents.tsv has a stale id"
        ]
    if inst.get("app_id") != app_id:
        return MISSING, [
            f"installation {inst_id} belongs to App {inst.get('app_id')} ({inst.get('app_slug')}), not {app_id}: agents.tsv is wrong"
        ]
    if inst.get("suspended_at"):
        return MISSING, [
            f"installation {inst_id} is suspended since {inst['suspended_at']}: the App can do nothing"
        ]
    granted = inst.get("permissions")
    if not isinstance(granted, dict):
        return UNREAD, [f"installation {inst_id}: GitHub gave no permissions for it"]

    details = differences(CODE, declared, GRANT, granted)
    if isinstance(requested, ReadError):
        return UNREAD, details + [f"could not read what the App asks for: {requested}"]

    asks_beyond_code = differences(CODE, declared, ASK, requested)
    unaccepted = differences(GRANT, granted, ASK, requested)
    accept_at = f"accept at https://github.com/organizations/{org}/settings/installations/{inst_id}"

    if not details and not asks_beyond_code and not unaccepted:
        return OK, [" ".join(f"{k}={v}" for k, v in sorted(granted.items()))]
    if unaccepted and not asks_beyond_code:
        # The code and the App's settings agree; only the org's click is missing.
        return PENDING, [f"waiting for the org to accept a change ({accept_at}):"] + [
            f"  {line}" for line in unaccepted
        ]
    if not unaccepted:
        # Settings and grant agree with each other, so one set of lines says it.
        return DRIFT, details
    return DRIFT, details + asks_beyond_code + [
        f"and the org has not accepted what the App's settings ask for ({accept_at})"
    ]


def check(agents, declared, github, org=ORG):
    """-> (exit code, report lines)."""
    results = []
    try:
        installations = org_installations(github, org)
    except ReadError as err:
        hint = ""
        if " 403 " in str(err) or " 404 " in str(err):
            hint = (
                " -- listing an org's App installations needs org Administration read:"
                " an org owner's gh login, or the vitruviansoftware-pulumi App token"
                " (an agent's own GH_TOKEN cannot; unset it to use your gh login)"
            )
        for name, _, _ in agents:
            results.append(
                (
                    name,
                    UNREAD,
                    ["the org's App installations could not be read (above)"],
                )
            )
        return _verdict(
            results,
            org,
            [f"Could not read the org's App installations: {err}{hint}", ""],
        )

    by_id = {inst.get("id"): inst for inst in installations}
    for name, app_id, inst_id in agents:
        inst = by_id.get(inst_id)
        requested = None
        if inst is not None and inst.get("app_id") == app_id:
            try:
                requested = requested_permissions(github, inst.get("app_slug"), app_id)
            except ReadError as err:
                requested = err
        results.append(
            (name, *judge(app_id, inst_id, declared[name], inst, requested, org))
        )

    listed = {app_id for _, app_id, _ in agents}
    for inst in installations:
        slug = inst.get("app_slug") or ""
        if AGENT_SLUG.match(slug) and inst.get("app_id") not in listed:
            results.append(
                (
                    slug,
                    UNLISTED,
                    [
                        f"App {inst.get('app_id')} is installed (installation {inst.get('id')}) but not in agents.tsv"
                    ],
                )
            )
    return _verdict(results, org)


def _verdict(results, org, preamble=()):
    width = max(len(name) for name, _, _ in results)
    lines = [
        f"Agent App permissions: tools/agent-app/permissions.tsv vs GitHub ({org})",
        "",
        *preamble,
    ]
    for name, state, details in results:
        # One detail fits on the App's line; more go underneath it.
        inline = details[0] if len(details) == 1 else ""
        lines.append(f"  {state:<11} {name:<{width}}  {inline}".rstrip())
        if len(details) > 1:
            lines.extend(f"  {'':<11} {'':<{width}}  {d}" for d in details)
    counts = {}
    for _, state, _ in results:
        counts[state] = counts.get(state, 0) + 1
    order = [OK, PENDING, DRIFT, MISSING, UNLISTED, UNREAD]
    lines += [
        "",
        f"{len(results)} Apps: "
        + ", ".join(f"{counts[s]} {s}" for s in order if s in counts)
        + ".",
    ]
    if UNREAD in counts:
        lines.append("NOT a pass: GitHub could not be read for every App.")
        return 2, lines
    if set(counts) != {OK}:
        lines.append(
            "How to fix: tools/agent-app/README.md, 'Changing an App's permissions'."
        )
        return 1, lines
    return 0, lines


# --------------------------------------------------------------------------
# Command line.
# --------------------------------------------------------------------------


def _here():
    # Under `bazel run` the files to judge are the committed ones in the
    # workspace, not the runfiles copies (agent-app.sh does the same).
    workspace = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if workspace:
        return os.path.join(workspace, "tools", "agent-app")
    return os.path.dirname(os.path.abspath(__file__))


def token():
    """-> (token, where it came from). ReadError when there is none."""
    for name in ("GH_TOKEN", "GITHUB_TOKEN"):
        if os.environ.get(name):
            return os.environ[name], name
    try:
        out = subprocess.run(
            ["gh", "auth", "token"],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as err:
        raise ReadError(f"no GH_TOKEN and `gh auth token` failed: {err}") from err
    if out.returncode != 0 or not out.stdout.strip():
        raise ReadError("no GH_TOKEN and no gh login: run `gh auth login`")
    return out.stdout.strip(), "your gh login"


def main(argv=None):
    here = _here()
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--agents", default=os.path.join(here, "agents.tsv"))
    parser.add_argument("--permissions", default=os.path.join(here, "permissions.tsv"))
    parser.add_argument("--org", default=ORG)
    args = parser.parse_args(argv)

    try:
        agents = load_agents(args.agents)
        declared = load_declared(args.permissions, agents)
    except FileError as err:
        print(f"permission-drift: {err}", file=sys.stderr)
        return 2
    try:
        tok, source = token()
    except ReadError as err:
        print(f"permission-drift: NOT CHECKED: {err}", file=sys.stderr)
        return 2
    print(f"(reading GitHub as {source})")
    code, lines = check(agents, declared, GitHub(tok), args.org)
    print("\n".join(lines))
    return code


if __name__ == "__main__":
    sys.exit(main())
