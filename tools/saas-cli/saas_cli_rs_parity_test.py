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
"""saas-cli, the Rust port, against saas-cli.sh: same exit code, stdout,
stderr, the same gcloud calls, and the same npx calls -- argv AND the
credentials each was handed in its environment -- on every case below. The
identity resolver is the real //tools/pulumi:resolve_identity.sh.

    bazel test //tools/saas-cli:saas_cli_rs_parity_test

One file is left out of the comparison on purpose: when the script `exec`s
the CLI its EXIT trap never runs, so the temp file it captured gcloud's
stderr in is left in $TMPDIR. The port keeps that in memory and leaves
nothing.
"""

import os
import sys

sys.path.insert(
    0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shell-compat")
)
from parity_harness import Case, Harness, need_env, write, write_exec  # noqa: E402

GCLOUD = r"""#!/usr/bin/env bash
printf '%s\n' "$*" >>"$LOGDIR/gcloud.log"
for p in ${FAKE_REAUTH_ON:-}; do
  case "$*" in *"$p"*) echo "ERROR: (gcloud.secrets.versions.access) Reauthentication failed." >&2; exit 0 ;; esac
done
for p in ${FAKE_DENY_ON:-}; do
  case "$*" in *"$p"*) echo "ERROR: (gcloud.secrets.versions.access) PERMISSION_DENIED: $p" >&2; echo "  more detail" >&2; exit 1 ;; esac
done
for p in ${FAKE_EMPTY_ON:-}; do
  case "$*" in *"$p"*) printf '\n\n'; exit 0 ;; esac
done
[ -n "${FAKE_WARN:-}" ] && echo "WARNING: $FAKE_WARN" >&2
case "$*" in
  *NEON_API_KEY*)    printf 'neon-key-SECRET\n\n' ;;
  *UPSTASH_API_KEY*) printf 'upstash-key-SECRET' ;;
  *UPSTASH_EMAIL*)   echo "robot@example.test" ;;
esac
"""

NPX = r"""#!/usr/bin/env bash
{
  printf 'ARGV:'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'
  printf 'ENV_NEON:%s\n' "${NEON_API_KEY-<unset>}"
  printf 'ENV_UPSTASH:%s %s\n' "${UPSTASH_EMAIL-<unset>}" "${UPSTASH_API_KEY-<unset>}"
} >>"$LOGDIR/npx.log"
echo "out line 1"
echo "err line 1" >&2
printf 'partial'
echo " out line 2"
for p in ${FAKE_NPX_FAIL_ON:-}; do case "$*" in *"$p"*) echo "Error: 401 Unauthorized" >&2; exit 3 ;; esac; done
[ "${FAKE_NO_NEWLINE:-0}" = 1 ] && printf 'tail without newline'
exit 0
"""

MAP = (
    "tabula/infra/build\trobot@example.test\tprj-demo-1234\tdemo\n"
    "dash/infra\trobot@example.test\t-\treference\n"
)


def setup(root):
    os.makedirs(root + "/log")
    write_exec(root + "/bin/gcloud", GCLOUD)
    write_exec(root + "/bin/npx", NPX)
    write(root + "/identities.tsv", MAP)


def case(name, args, env=None, **kw):
    e = {
        "LOGDIR": "{root}/log",
        "GCLOUD_BIN": "{root}/bin/gcloud",
        "NPX_BIN": "{root}/bin/npx",
        "GCP_IDENTITY_MAP": "{root}/identities.tsv",
        "GCP_IDENTITY_RESOLVER": RESOLVER,
    }
    e.update(env or {})
    return Case(
        name=name,
        args=args,
        env=e,
        setup=setup,
        ignore=[r"^tmp/tmp\.[A-Za-z0-9]+$"],
        **kw,
    )


def cases():
    yield case("neon: projects list", ["neon", "projects", "list"])
    yield case(
        "neon: args verbatim",
        [
            "neon",
            "connection-string",
            "my project",
            "--database-name",
            "main",
            "",
            "a'b\"c",
        ],
    )
    yield case("neon: no args", ["neon"])
    yield case(
        "neon: version override", ["neon", "me"], env={"NEONCTL_VERSION": "9.9.9"}
    )
    yield case("neon: npx on PATH by name", ["neon", "me"], env={"NPX_BIN": "npx"})
    yield case(
        "neon: npx exits non-zero", ["neon", "me"], env={"FAKE_NPX_FAIL_ON": "me"}
    )
    yield case(
        "neon: auth failure",
        ["neon", "projects", "list"],
        env={"FAKE_REAUTH_ON": "NEON_API_KEY"},
    )
    yield case(
        "neon: permission denied",
        ["neon", "projects", "list"],
        env={"FAKE_DENY_ON": "NEON_API_KEY"},
    )
    yield case(
        "neon: empty secret",
        ["neon", "projects", "list"],
        env={"FAKE_EMPTY_ON": "NEON_API_KEY"},
    )
    yield case(
        "neon: a warning is not an error",
        ["neon", "x"],
        env={"FAKE_WARN": "deprecated"},
    )
    yield case("neon: gcloud missing", ["neon", "x"], env={"GCLOUD_BIN": "{root}/nope"})
    yield case("upstash: redis list", ["upstash", "redis", "list"])
    yield case(
        "upstash: version override",
        ["upstash", "redis", "get", "id-1"],
        env={"UPSTASH_CLI_VERSION": "2.0.0"},
    )
    yield case(
        "upstash: email fails",
        ["upstash", "redis", "list"],
        env={"FAKE_DENY_ON": "UPSTASH_EMAIL"},
    )
    yield case(
        "upstash: key empty",
        ["upstash", "redis", "list"],
        env={"FAKE_EMPTY_ON": "UPSTASH_API_KEY"},
    )
    yield case("whoami: both work", ["whoami"])
    yield case("whoami: extra args ignored", ["whoami", "extra"])
    yield case(
        "whoami: output without a final newline",
        ["whoami"],
        env={"FAKE_NO_NEWLINE": "1"},
    )
    yield case("whoami: neon fails", ["whoami"], env={"FAKE_NPX_FAIL_ON": "me"})
    yield case("whoami: upstash fails", ["whoami"], env={"FAKE_NPX_FAIL_ON": "redis"})
    yield case("whoami: both fail", ["whoami"], env={"FAKE_NPX_FAIL_ON": "me redis"})
    yield case(
        "whoami: a secret fails first",
        ["whoami"],
        env={"FAKE_REAUTH_ON": "UPSTASH_API_KEY"},
    )
    yield case("whoami: npx missing", ["whoami"], env={"NPX_BIN": "{root}/no-npx"})
    yield case("unknown subcommand", ["bogus"])
    yield case("no subcommand", [])
    yield case("empty subcommand", [""])
    yield case("CRED_DIR not listed", ["neon", "x"], env={"CRED_DIR": "other/infra"})
    yield case("CRED_DIR with project '-'", ["whoami"], env={"CRED_DIR": "dash/infra"})
    yield case(
        "map missing", ["neon", "x"], env={"GCP_IDENTITY_MAP": "{root}/nope.tsv"}
    )
    yield case(
        "resolver missing",
        ["neon", "x"],
        env={"GCP_IDENTITY_RESOLVER": "{root}/nope.sh"},
    )
    yield case(
        "default map under BUILD_WORKSPACE_DIRECTORY",
        ["neon", "x"],
        env={"GCP_IDENTITY_MAP": None, "BUILD_WORKSPACE_DIRECTORY": "{root}"},
    )


RESOLVER = ""


def main():
    global RESOLVER
    RESOLVER = os.path.abspath(need_env("RESOLVE_IDENTITY"))
    h = Harness("saas-cli parity", need_env("SAAS_CLI_SH"), need_env("SAAS_CLI_RS"))
    for c in cases():
        h.check(c)
    return h.finish()


if __name__ == "__main__":
    sys.exit(main())
