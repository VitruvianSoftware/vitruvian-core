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
"""Rotate the Pulumi Cloud token CI uses, without anyone seeing it.

    bazel run //tools/pulumi:rotate-access-token             # mint, check, store
    bazel run //tools/pulumi:rotate-access-token -- --cleanup                 # later: delete old CI tokens
    bazel run //tools/pulumi:rotate-access-token -- --cleanup --delete-old ID # ...or a specific one

Rotate:
  1. Signs in to Pulumi Cloud as YOU, with the token your `pulumi login`
     already saved (or $PULUMI_ACCESS_TOKEN).
  2. Mints a new personal token labelled "github-actions: <repo> ..." so later
     rotations can find it.
  3. Checks the new token works (same Pulumi user).
  4. Stores it as the repo's PULUMI_ACCESS_TOKEN, in both the Actions and the
     Dependabot stores, over stdin. It is never printed.

Cleanup is a separate step on purpose: delete the old token only after a CI
run that uses Pulumi has gone green on the new one. It deletes older tokens
carrying the label, plus any id you name with --delete-old, and always asks
first. It refuses to delete a token used in the last few minutes, which
protects the token you are signed in with.

The repo-config Pulumi stack also writes the Dependabot copy, from this same
Actions secret, so the two stay in agreement.
"""

import argparse
import datetime
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = os.environ.get("PULUMI_API", "https://api.pulumi.com")
REPO = os.environ.get("ROTATE_REPO", "VitruvianSoftware/vitruvian-core")
SECRET = "PULUMI_ACCESS_TOKEN"
LABEL = f"github-actions: {REPO}"
RECENT_USE_SECONDS = 300


class Fail(Exception):
    pass


def ok(msg):
    print(f"  ✓ {msg}")


def warn(msg):
    print(f"  ! {msg}")


def operator_token():
    """The token of whoever runs this: env first, then `pulumi login`'s file."""
    if os.environ.get("PULUMI_ACCESS_TOKEN"):
        return os.environ["PULUMI_ACCESS_TOKEN"]
    path = os.path.expanduser("~/.pulumi/credentials.json")
    try:
        with open(path) as f:
            return json.load(f)["accessTokens"][API]
    except (OSError, KeyError, ValueError):
        raise Fail(f"not signed in to {API} -- run `pulumi login` first")


def api(token, method, path, body=None):
    req = urllib.request.Request(
        API + path,
        method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={
            "Authorization": f"token {token}",
            "Accept": "application/vnd.pulumi+8",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as e:
        raise Fail(f"Pulumi Cloud said {e.code} to {method} {path}")
    except urllib.error.URLError as e:
        raise Fail(f"could not reach {API}: {e.reason}")
    return json.loads(raw) if raw else {}


def whoami(token):
    return api(token, "GET", "/api/user")["githubLogin"]


def store_secret(value, dependabot):
    cmd = ["gh", "secret", "set", SECRET, "--repo", REPO]
    if dependabot:
        cmd += ["--app", "dependabot"]
    done = subprocess.run(cmd, input=value, text=True, capture_output=True, check=False)
    if done.returncode != 0:
        raise Fail(f"gh could not store {SECRET}: {done.stderr.strip()}")


def rotate(token):
    user = whoami(token)
    ok(f"signed in to Pulumi Cloud as {user}")
    today = datetime.datetime.now(tz=datetime.timezone.utc).date().isoformat()
    created = api(
        token,
        "POST",
        "/api/user/tokens",
        {"description": f"{LABEL} (rotated {today})", "expires": 0},
    )
    new = created["tokenValue"]
    ok(f"minted a new token (id {created['id']})")
    if whoami(new) != user:
        raise Fail("the new token signs in as a different user -- not storing it")
    ok("the new token works")
    for dependabot in (False, True):
        store_secret(new, dependabot)
    ok(f"stored {SECRET} on {REPO} (Actions and Dependabot); never printed")
    print(
        "\nNext: once a CI run that uses Pulumi is green, delete the old token:\n"
        "  bazel run //tools/pulumi:rotate-access-token -- --cleanup"
    )


def cleanup(token, extra_ids, assume_yes, ask=input):
    tokens = api(token, "GET", "/api/user/tokens")["tokens"]
    labelled = sorted(
        (t for t in tokens if t.get("description", "").startswith(LABEL)),
        key=lambda t: t["created"],
    )
    # Keep the newest labelled token: that is the one CI now holds.
    doomed = labelled[:-1] + [t for t in tokens if t["id"] in extra_ids]
    unknown = set(extra_ids) - {t["id"] for t in tokens}
    if unknown:
        raise Fail(f"no such token: {', '.join(sorted(unknown))}")
    if labelled and labelled[-1]["id"] in extra_ids:
        raise Fail("that id is the newest CI token -- CI is using it")
    if not doomed:
        ok("nothing to delete")
        if not labelled:
            warn(
                "no token carries the CI label yet. If an older token was CI's, "
                "pass its id with --delete-old. Your tokens:"
            )
            for t in tokens:
                print(
                    f"      {t['id']}  {t['created'][:10]}  {t.get('description', '')}"
                )
        return
    now = time.time()
    for t in doomed:
        desc = f"{t['id']} ({t.get('description', '')}, created {t['created'][:10]})"
        if t.get("lastUsed", 0) and now - t["lastUsed"] < RECENT_USE_SECONDS:
            warn(f"skipping {desc}: used in the last few minutes")
            continue
        if not assume_yes and ask(f"? Delete {desc}? [y/N] ").strip().lower() not in (
            "y",
            "yes",
        ):
            warn(f"kept {desc}")
            continue
        api(token, "DELETE", f"/api/user/tokens/{t['id']}")
        ok(f"deleted {desc}")


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument(
        "--cleanup",
        action="store_true",
        help="delete old CI tokens instead of rotating",
    )
    p.add_argument(
        "--delete-old",
        action="append",
        default=[],
        metavar="ID",
        help="also delete this token id (with --cleanup)",
    )
    p.add_argument("--yes", action="store_true", help="don't ask before deleting")
    args = p.parse_args(argv)
    if args.delete_old and not args.cleanup:
        p.error("--delete-old only goes with --cleanup")
    try:
        token = operator_token()
        if args.cleanup:
            cleanup(token, args.delete_old, args.yes)
        else:
            rotate(token)
    except Fail as e:
        print(f"  ✗ {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
