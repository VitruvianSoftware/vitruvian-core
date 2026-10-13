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

"""Set up, on each registry, the trust that lets the workflow publish.

    bazel run //tools/registry-trust:setup -- --dry-run
    bazel run //tools/registry-trust:setup
    bazel run //tools/registry-trust:setup -- --only crates

WHY THIS EXISTS. Publishing is in code and keyless. What was not in code is
the other half: telling each registry which repository, workflow file and
environment it should trust. On 2026-10-13 that was one hand-made API call to
crates.io and a form on PyPI. This makes it a command whose values are read
from the code (//tools/registry-trust:inventory), never typed.

  crates.io  Lists the trusted publishers of each crate and creates the one
             that is missing. Running it again changes nothing.
  npm        Hands the packages to //tools/npm-trusted-publisher:setup, which
             already does this with `npm trust` and one two-factor prompt.
  PyPI       Has no API for trusted publishers: they are made on a web page.
             This prints the exact values to enter and the page to enter
             them on. It cannot tell whether they are entered already.

A registry will not attach a trusted publisher to a package that does not
exist. Such a package is reported as "not yet on the registry" and needs its
one-time first publish (docs/engineering/registry-trust.md).

THE CARGO TOKEN is read when it is needed and only then: from
CARGO_REGISTRY_TOKEN, or the file `cargo login` writes
($CARGO_HOME or ~/.cargo, credentials.toml). It is sent to crates.io in the
Authorization header and to nothing else. It is never printed, logged or
written. `--dry-run` does not read it and makes no request that needs it.

Exit: 0 done · 1 a registry refused something · 2 setup error
"""

import json
import os
import subprocess
import sys
import tempfile
import tomllib
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check  # noqa: E402
import inventory  # noqa: E402

CONFIGS = "https://crates.io/api/v1/trusted_publishing/github_configs"
NPM_SETUP = "tools/npm-trusted-publisher/setup.sh"
RUNBOOK = "docs/engineering/registry-trust.md"


class SetupError(Exception):
    pass


# --- crates.io ------------------------------------------------------------------


def cargo_token(env):
    """The token `cargo` would use, or a SetupError that says how to get one.
    The value goes to the caller and nowhere else."""
    if env.get("CARGO_REGISTRY_TOKEN"):
        return env["CARGO_REGISTRY_TOKEN"]
    home = env.get("CARGO_HOME") or os.path.join(env.get("HOME", ""), ".cargo")
    for name in ("credentials.toml", "credentials"):
        try:
            with open(os.path.join(home, name), "rb") as handle:
                token = tomllib.load(handle).get("registry", {}).get("token")
        except OSError:
            continue
        except tomllib.TOMLDecodeError as error:
            # Not `from error`: the parser's message can quote the file.
            raise SetupError(f"cargo's {name} cannot be read as TOML") from None
        if token:
            return token
    raise SetupError(
        "no crates.io token: run `cargo login` (a token with the "
        "trusted-publishing scope), or set CARGO_REGISTRY_TOKEN, then re-run"
    )


def crates_request(method, url, token, body=None):
    parts = urllib.parse.urlsplit(url)
    if parts.scheme != "https" or parts.hostname != "crates.io":
        raise ValueError("the cargo token goes to https://crates.io and nowhere else")
    headers = {
        "Authorization": token,
        "User-Agent": check.USER_AGENT,
        "Accept": "application/json",
    }
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    return urllib.request.Request(url, data=data, headers=headers, method=method)


def crates_send(method, url, token, body=None):
    try:
        with urllib.request.urlopen(
            crates_request(method, url, token, body), timeout=30
        ) as answer:
            return answer.status, answer.read()
    except urllib.error.HTTPError as error:
        status, text = error.code, error.read()
        error.close()
        return status, text


def _detail(body):
    """What crates.io said went wrong: its own words, and nothing we sent."""
    try:
        errors = json.loads(body).get("errors", [])
    except (ValueError, AttributeError):
        return "no reason given"
    return "; ".join(str(e.get("detail")) for e in errors) or "no reason given"


def _wanted(package):
    return {
        "crate": package.name,
        "repository_owner": package.owner,
        "repository_name": package.repo,
        "workflow_filename": package.workflow,
        "environment": package.environment or None,
    }


def _same(config, wanted):
    return (
        (config.get("repository_owner") or "").lower()
        == wanted["repository_owner"].lower()
        and (config.get("repository_name") or "").lower()
        == wanted["repository_name"].lower()
        and config.get("workflow_filename") == wanted["workflow_filename"]
        and (config.get("environment") or None) == wanted["environment"]
    )


def _existing(package, token, send):
    configs, page = [], f"?crate={urllib.parse.quote(package.name)}"
    while page:
        status, body = send("GET", CONFIGS + page, token)
        if status != 200:
            raise SetupError(
                f"HTTP {status} listing its trusted publishers: {_detail(body)}"
            )
        data = json.loads(body)
        configs += data.get("github_configs", [])
        page = (data.get("meta") or {}).get("next_page")
    return configs


def _target(package):
    environment = f" environment {package.environment}" if package.environment else ""
    return f"{package.repository} {package.workflow}{environment}"


def setup_crates(packages, dry_run, env, fetch, send, out, err):
    counts = {"configured": 0, "already": 0, "failed": 0, "unpublished": 0}
    print("crates.io:", file=out)
    token = None
    for package in packages:
        status, _ = fetch(f"https://crates.io/api/v1/crates/{package.name}")
        if status == 404:
            print(
                f"  -- {package.name} is not on crates.io yet; publish it once "
                f"({RUNBOOK}), then re-run",
                file=out,
            )
            counts["unpublished"] += 1
            continue
        if status != 200:
            raise SetupError(
                f"crates.io answered HTTP {status} for {package.name}; "
                "refusing to guess whether it is published"
            )
        if dry_run:
            print(
                f"  DRY_RUN {package.name} -> {_target(package)} "
                "(created only if crates.io does not list it already)",
                file=out,
            )
            counts["configured"] += 1
            continue
        if token is None:
            token = cargo_token(env)
        wanted = _wanted(package)
        try:
            configs = _existing(package, token, send)
        except SetupError as error:
            print(f"  ✗ {package.name} -- {error}", file=err)
            counts["failed"] += 1
            continue
        if any(_same(config, wanted) for config in configs):
            print(f"  ok {package.name} (already configured)", file=out)
            counts["already"] += 1
            continue
        for config in configs:
            print(
                f"  note: {package.name} also trusts "
                f"{config.get('repository_owner')}/{config.get('repository_name')} "
                f"{config.get('workflow_filename')}; left as it is",
                file=out,
            )
        status, body = send("POST", CONFIGS, token, {"github_config": wanted})
        if status == 200:
            print(f"  + {package.name} -> {_target(package)}", file=out)
            counts["configured"] += 1
        else:
            print(f"  ✗ {package.name} -- HTTP {status}: {_detail(body)}", file=err)
            counts["failed"] += 1
    print(
        f"  {counts['configured']} {'to configure' if dry_run else 'configured'}, "
        f"{counts['already']} already set, {counts['failed']} failed, "
        f"{counts['unpublished']} not yet on the registry.",
        file=out,
    )
    return 1 if counts["failed"] else 0


# --- PyPI -----------------------------------------------------------------------


def setup_pypi(packages, fetch, out):
    print("PyPI:", file=out)
    print(
        "  PyPI has no API for trusted publishers. Enter these by hand, once a\n"
        "  project; nothing here can tell whether they are entered already.",
        file=out,
    )
    for package in packages:
        status, _ = fetch(f"https://pypi.org/pypi/{package.name}/json")
        if status not in (200, 404):
            raise SetupError(
                f"PyPI answered HTTP {status} for {package.name}; "
                "refusing to guess whether it is published"
            )
        if status == 200:
            page = (
                f"https://pypi.org/manage/project/{package.name}/settings/publishing/"
            )
            print(
                f"  {package.name} (on PyPI): add a GitHub publisher at\n      {page}",
                file=out,
            )
        else:
            print(
                f"  {package.name} is not on PyPI yet: add a pending GitHub publisher at\n"
                "      https://pypi.org/manage/account/publishing/\n"
                f"      PyPI Project Name: {package.name}",
                file=out,
            )
        print(
            f"      Owner: {package.owner}\n"
            f"      Repository name: {package.repo}\n"
            f"      Workflow name: {package.workflow}\n"
            f"      Environment name: {package.environment or '(leave empty)'}",
            file=out,
        )
    print(f"  {len(packages)} to enter by hand.", file=out)
    return 0


# --- npm ------------------------------------------------------------------------


def run_npm_setup(command, env):
    return subprocess.call(command, env=env)


def setup_npm(packages, dry_run, root, env, fetch, run_npm, out):
    print("npm:", file=out)
    if dry_run:
        unpublished = 0
        for package in packages:
            name = urllib.parse.quote(package.name, safe="@")
            status, _ = fetch(f"https://registry.npmjs.org/{name}")
            if status == 404:
                print(
                    f"  -- {package.name} is not on npm yet; publish it once "
                    f"({RUNBOOK}), then re-run",
                    file=out,
                )
                unpublished += 1
            elif status == 200:
                print(f"  DRY_RUN {package.name} -> {_target(package)}", file=out)
            else:
                raise SetupError(
                    f"npm answered HTTP {status} for {package.name}; "
                    "refusing to guess whether it is published"
                )
        print(
            f"  {len(packages) - unpublished} to hand to "
            "//tools/npm-trusted-publisher:setup (it skips what is set already), "
            f"{unpublished} not yet on the registry.",
            file=out,
        )
        return 0
    handle, listed = tempfile.mkstemp(prefix="registry-trust-npm-", suffix=".tsv")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as file:
            for package in sorted(packages, key=lambda p: p.file):
                file.write(
                    f"{package.file}\t{package.repository}\t{package.workflow}\n"
                )
        out.flush()
        child = dict(env, NPM_TP_PACKAGES=listed, BUILD_WORKSPACE_DIRECTORY=root)
        return 1 if run_npm(["bash", os.path.join(root, NPM_SETUP)], child) else 0
    finally:
        os.remove(listed)


# --- all of it ------------------------------------------------------------------


def main(
    argv,
    root=None,
    env=None,
    fetch=check.http_fetch,
    send=crates_send,
    run_npm=run_npm_setup,
    out=sys.stdout,
    err=sys.stderr,
):
    env = os.environ if env is None else env
    root = root or inventory.root_folder()
    dry_run, only, argv = False, None, list(argv)
    while argv:
        flag = argv.pop(0)
        if flag == "--dry-run":
            dry_run = True
        elif flag == "--only" and argv and argv[0] in inventory.REGISTRIES:
            only = argv.pop(0)
        else:
            print(f"registry-trust: unknown flag: {flag}", file=err)
            print("  usage: setup [--dry-run] [--only npm|pypi|crates]", file=err)
            return 2
    found = inventory.load(root)
    if found.problems or not found.packages:
        for problem in found.problems or ["the inventory is empty"]:
            print(f"registry-trust: {problem}", file=err)
        return 2

    def mine(registry):
        if only not in (None, registry):
            return []
        return [p for p in found.packages if p.registry == registry]

    code = 0
    try:
        if mine("npm"):
            code |= setup_npm(mine("npm"), dry_run, root, env, fetch, run_npm, out)
        if mine("crates"):
            code |= setup_crates(mine("crates"), dry_run, env, fetch, send, out, err)
        if mine("pypi"):
            code |= setup_pypi(mine("pypi"), fetch, out)
    except (SetupError, check.RegistryError) as error:
        print(f"registry-trust: {error}", file=err)
        return 2
    if code:
        print(
            "registry-trust: something failed. Fix it and re-run; what is set "
            "already is skipped, so this is safe to repeat.",
            file=err,
        )
    elif not dry_run:
        print("  Verify with: bazel run //tools/registry-trust:check", file=out)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
