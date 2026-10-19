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

"""How is main's merge queue doing over a window of days?

    bazel run //tools/merge-queue-stats -- --since 2026-10-05 --until 2026-10-19
    python3 tools/merge-queue-stats/merge_queue_stats.py --since 2026-10-19

Prints one Markdown report, the same shape every time, so a change to the
queue can be judged by running it on the window before and the window after.
It was written to judge the switch from ALLGREEN to HEADGREEN grouping; the
tracking issue holds both reports.

  Speed     pull requests merged through the queue, and for each the time
            from its LAST entry into the queue to its merge (the attempt that
            worked) and from its FIRST entry (with every retry); median, p90.
  Ejections every removal from the queue by GitHub itself, by reason, across
            all PRs updated in the window (a removal by a person is not one,
            and neither is the "merged" removal every merge makes).
  Breakage  push runs on main that failed, by workflow, and reverts on main.
            A grouping that merges something it should not shows up here.

Reads as the token in GH_TOKEN, else GITHUB_TOKEN, else `gh auth token`.
Standard library only. Exit: 0 printed · 2 GitHub could not be read.
"""

import argparse
import datetime as dt
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

API = os.environ.get("GITHUB_API_URL", "https://api.github.com")
QUEUE_BOT = "github-merge-queue"

QUERY = """
query($q: String!, $after: String) {
  search(query: $q, type: ISSUE, first: 50, after: $after) {
    pageInfo { hasNextPage endCursor }
    nodes {
      ... on PullRequest {
        number
        mergedAt
        timelineItems(first: 100, itemTypes: [ADDED_TO_MERGE_QUEUE_EVENT, REMOVED_FROM_MERGE_QUEUE_EVENT]) {
          nodes {
            __typename
            ... on AddedToMergeQueueEvent { createdAt }
            ... on RemovedFromMergeQueueEvent { createdAt reason actor { login } }
          }
        }
      }
    }
  }
}
"""


def parse_time(value):
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def percentile(values, fraction):
    """Nearest-rank percentile; None for no values."""
    if not values:
        return None
    ordered = sorted(values)
    rank = max(1, int(round(fraction * len(ordered) + 0.5 - 1e-9)))
    return ordered[min(rank, len(ordered)) - 1]


def minutes(value):
    return "–" if value is None else f"{value:.1f} min"


def queue_times(pulls, since, until):
    """(last-entry minutes, first-entry minutes) for PRs merged in the window
    after at least one entry into the queue."""
    last, first = [], []
    for pr in pulls:
        if not pr.get("mergedAt"):
            continue
        merged = parse_time(pr["mergedAt"])
        if not since <= merged < until:
            continue
        added = sorted(
            parse_time(e["createdAt"])
            for e in pr["timelineItems"]["nodes"]
            if e.get("__typename") == "AddedToMergeQueueEvent"
            and parse_time(e["createdAt"]) <= merged
        )
        if not added:
            continue
        last.append((merged - added[-1]).total_seconds() / 60)
        first.append((merged - added[0]).total_seconds() / 60)
    return last, first


def ejections(pulls, since, until):
    """Removals by the queue itself in the window, counted by reason."""
    counts = {}
    for pr in pulls:
        for e in pr["timelineItems"]["nodes"]:
            if e.get("__typename") != "RemovedFromMergeQueueEvent":
                continue
            if not since <= parse_time(e["createdAt"]) < until:
                continue
            if ((e.get("actor") or {}).get("login") or "") != QUEUE_BOT:
                continue
            reason = (e.get("reason") or "unknown").strip() or "unknown"
            if reason.lower() == "merged":  # every merge leaves the queue this way
                continue
            counts[reason] = counts.get(reason, 0) + 1
    return counts


def failed_runs(runs):
    """Failed push runs on main, counted by workflow."""
    counts = {}
    for run in runs:
        if run.get("conclusion") in ("failure", "timed_out"):
            counts[run["name"]] = counts.get(run["name"], 0) + 1
    return counts


def report(repo, since, until, pulls, runs, reverts):
    last, first = queue_times(pulls, since, until)
    eject = ejections(pulls, since, until)
    failed = failed_runs(runs)
    days = max((until - since).total_seconds() / 86400, 1e-9)
    lines = [
        f"### Merge queue, {repo}, {since:%Y-%m-%d %H:%M} to {until:%Y-%m-%d %H:%M} UTC",
        "",
        "| Speed | |",
        "|---|---|",
        f"| PRs merged through the queue | {len(last)} ({len(last) / days:.1f}/day) |",
        f"| Last entry → merged | median {minutes(percentile(last, 0.5))}, p90 {minutes(percentile(last, 0.9))} |",
        f"| First entry → merged (with retries) | median {minutes(percentile(first, 0.5))}, p90 {minutes(percentile(first, 0.9))} |",
        "",
        f"**Ejections by the queue:** {sum(eject.values())}",
        "",
    ]
    lines += [
        f"- {reason}: {n}" for reason, n in sorted(eject.items(), key=lambda kv: -kv[1])
    ] or ["- none"]
    lines += [
        "",
        f"**Breakage on main:** {sum(failed.values())} failed push run(s), {len(reverts)} revert(s)",
        "",
    ]
    lines += [
        f"- {name}: {n}" for name, n in sorted(failed.items(), key=lambda kv: -kv[1])
    ] or ["- no failed push runs"]
    lines += [f"- revert: {r}" for r in reverts]
    return "\n".join(lines) + "\n"


def token():
    for name in ("GH_TOKEN", "GITHUB_TOKEN"):
        if os.environ.get(name):
            return os.environ[name]
    try:
        return subprocess.run(
            ["gh", "auth", "token"], capture_output=True, text=True, check=True
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def call(tok, method, path, body=None):
    request = urllib.request.Request(
        API + path,
        method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {tok}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def fetch_pulls(tok, repo, since, until):
    query = f"repo:{repo} is:pr base:main updated:{since:%Y-%m-%dT%H:%M:%SZ}..{until:%Y-%m-%dT%H:%M:%SZ}"
    pulls, after = [], None
    while True:
        data = call(
            tok,
            "POST",
            "/graphql",
            {"query": QUERY, "variables": {"q": query, "after": after}},
        )
        if data.get("errors"):
            raise RuntimeError(data["errors"])
        page = data["data"]["search"]
        pulls += [n for n in page["nodes"] if n]
        if not page["pageInfo"]["hasNextPage"]:
            return pulls
        after = page["pageInfo"]["endCursor"]


def fetch_runs(tok, repo, since, until):
    # Filtered by conclusion on GitHub's side: a listing stops at 1,000 runs,
    # and main has more than that in two weeks.
    created = urllib.parse.quote(
        f"{since:%Y-%m-%dT%H:%M:%SZ}..{until:%Y-%m-%dT%H:%M:%SZ}"
    )
    runs = []
    for status in ("failure", "timed_out"):
        page = 1
        while True:
            data = call(
                tok,
                "GET",
                f"/repos/{repo}/actions/runs?branch=main&event=push&status={status}&created={created}&per_page=100&page={page}",
            )
            runs += data["workflow_runs"]
            if len(data["workflow_runs"]) < 100:
                break
            page += 1
    return runs


def fetch_reverts(tok, repo, since, until):
    reverts, page = [], 1
    while True:
        data = call(
            tok,
            "GET",
            f"/repos/{repo}/commits?sha=main&since={since:%Y-%m-%dT%H:%M:%SZ}&until={until:%Y-%m-%dT%H:%M:%SZ}&per_page=100&page={page}",
        )
        reverts += [
            c["commit"]["message"].splitlines()[0]
            for c in data
            if c["commit"]["message"].startswith("Revert ")
        ]
        if len(data) < 100:
            return reverts
        page += 1


def day(value):
    return dt.datetime.fromisoformat(value).replace(tzinfo=dt.timezone.utc)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--since", required=True, type=day, help="UTC date or datetime, e.g. 2026-10-05"
    )
    parser.add_argument(
        "--until", type=day, default=None, help="UTC date or datetime (default: now)"
    )
    parser.add_argument("--repo", default="VitruvianSoftware/vitruvian-core")
    args = parser.parse_args(argv)
    until = args.until or dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    tok = token()
    if not tok:
        print(
            "merge-queue-stats: no token (GH_TOKEN, GITHUB_TOKEN or gh auth token)",
            file=sys.stderr,
        )
        return 2
    try:
        pulls = fetch_pulls(tok, args.repo, args.since, until)
        runs = fetch_runs(tok, args.repo, args.since, until)
        reverts = fetch_reverts(tok, args.repo, args.since, until)
    except (urllib.error.URLError, RuntimeError, KeyError) as error:
        print(f"merge-queue-stats: could not read GitHub: {error}", file=sys.stderr)
        return 2
    sys.stdout.write(report(args.repo, args.since, until, pulls, runs, reverts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
