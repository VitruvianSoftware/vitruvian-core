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
"""gcp-secrets, the Rust port, against gcp-secrets.sh: same exit code,
stdout, stderr, and the same gcloud calls (argv and what each got on stdin),
on every case below. The identity resolver is the real
//tools/pulumi:resolve_identity.sh.

    bazel test //tools/gcp-secrets:gcp_secrets_rs_parity_test
"""

import os
import sys

sys.path.insert(
    0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shell-compat")
)
from parity_harness import Case, Harness, need_env, write, write_exec  # noqa: E402

GCLOUD = r"""#!/usr/bin/env bash
args="$*"
stdin_data=""
case "$args" in *"--data-file=-"*) stdin_data="$(cat; echo .)"; stdin_data="${stdin_data%.}" ;; esac
printf '%s|%s\n' "$stdin_data" "$args" >>"$LOGDIR/gcloud.log"
for p in ${FAKE_REAUTH_ON:-}; do
  case "$args" in *"$p"*)
    echo "ERROR: (gcloud.$p) There was a problem refreshing your current auth tokens: Reauthentication failed." >&2
    exit 0 ;;
  esac
done
for p in ${FAKE_FAIL_ON:-}; do
  case "$args" in *"$p"*) echo "permission denied on $p" >&2; echo "second line" >&2; exit 1 ;; esac
done
[ -n "${FAKE_WARN:-}" ] && echo "WARNING: ${FAKE_WARN}" >&2
case "$args" in
  *"secrets list"*)
    for s in ${FAKE_SECRETS-ALPHA_KEY BETA_KEY}; do
      case "$s" in */*) echo "$s" ;; *) echo "projects/prj-demo-1234/secrets/$s" ;; esac
    done ;;
  *"secrets versions list"*)
    for s in ${SEEDED:-}; do
      name="${s%%=*}"; n="${s#*=}"; [ "$n" = "$s" ] && n=1
      case "$args" in *" $name "*)
        i=1; while [ "$i" -le "$n" ]; do echo "projects/prj-demo-1234/secrets/$name/versions/$i"; i=$((i+1)); done
        exit 0 ;;
      esac
    done
    [ -n "${FAKE_BLANKS:-}" ] && printf '\n\n'
    : ;;
  *"versions add"*) [ "${FAKE_ADD_FAIL:-0}" = 1 ] && { echo "denied" >&2; exit 1; }; echo "Created version" ;;
esac
"""

MAP = (
    "# comment line\n"
    "demo/infra/build\trobot@example.test\tprj-demo-1234\tdemo build project\n"
    "dash/infra\trobot@example.test\t-\treference\n"
    "noproj/infra\trobot@example.test\n"
    "-\tignored@example.test\tprj-x\treference-only\n"
)


def setup(root):
    write_exec(root + "/bin/gcloud", GCLOUD)
    os.makedirs(root + "/log")
    write(root + "/identities.tsv", MAP)


def case(name, args, stdin=b"", env=None, **kw):
    e = {
        "LOGDIR": "{root}/log",
        "GCLOUD_BIN": "{root}/bin/gcloud",
        "GCP_IDENTITY_MAP": "{root}/identities.tsv",
        "GCP_IDENTITY_RESOLVER": RESOLVER,
    }
    e.update(env or {})
    return Case(name=name, args=args, stdin=stdin, env=e, setup=setup, **kw)


def cases():
    D = "demo/infra/build"
    yield case("status: nothing seeded", ["status", D])
    yield case("status: mixed", ["status", D], env={"SEEDED": "ALPHA_KEY=3"})
    yield case(
        "status: all seeded", ["status", D], env={"SEEDED": "ALPHA_KEY BETA_KEY=2"}
    )
    yield case("status: no secrets", ["status", D], env={"FAKE_SECRETS": ""})
    yield case(
        "status: odd names",
        ["status", D],
        env={
            "FAKE_SECRETS": "A_VERY_LONG_SECRET_NAME_THAT_EXCEEDS_THIRTY_TWO plain/ bare"
        },
    )
    yield case(
        "status: blank lines in versions", ["status", D], env={"FAKE_BLANKS": "1"}
    )
    yield case(
        "status: reauth on list", ["status", D], env={"FAKE_REAUTH_ON": "secrets list"}
    )
    yield case(
        "status: failure on list", ["status", D], env={"FAKE_FAIL_ON": "secrets list"}
    )
    yield case(
        "status: failure mid-table", ["status", D], env={"FAKE_FAIL_ON": "BETA_KEY"}
    )
    yield case(
        "status: reauth mid-table", ["status", D], env={"FAKE_REAUTH_ON": "BETA_KEY"}
    )
    yield case(
        "status: a warning is not an error",
        ["status", D],
        env={"FAKE_WARN": "deprecated flag"},
    )
    yield case("status: extra names ignored", ["status", D, "X"])
    yield case("seed: one secret", ["seed", D, "ALPHA_KEY"], stdin=b"sup3r-s3cret\n")
    yield case(
        "seed: value without newline", ["seed", D, "ALPHA_KEY"], stdin=b"no-newline"
    )
    yield case(
        "seed: backslashes and spaces kept",
        ["seed", D, "ALPHA_KEY"],
        stdin=b"  a\\b c \\n  \n",
    )
    yield case(
        "seed: already seeded",
        ["seed", D, "ALPHA_KEY"],
        stdin=b"another\n",
        env={"SEEDED": "ALPHA_KEY=2"},
    )
    yield case(
        "seed: --force rotates",
        ["seed", D, "--force", "ALPHA_KEY"],
        stdin=b"rotated\n",
        env={"SEEDED": "ALPHA_KEY"},
    )
    yield case(
        "seed: --force after names",
        ["seed", D, "ALPHA_KEY", "--force"],
        stdin=b"rotated\n",
        env={"SEEDED": "ALPHA_KEY"},
    )
    yield case("seed: empty input skips", ["seed", D, "ALPHA_KEY"], stdin=b"\n")
    yield case("seed: no stdin at all", ["seed", D, "ALPHA_KEY"], stdin=b"")
    yield case(
        "seed: several names, several lines",
        ["seed", D, "A", "B", "C"],
        stdin=b"one\n\nthree\n",
    )
    yield case(
        "seed: discovers the unseeded",
        ["seed", D],
        stdin=b"v1\n",
        env={"SEEDED": "ALPHA_KEY"},
    )
    yield case("seed: discovers all", ["seed", D], stdin=b"v1\nv2\n")
    yield case("seed: nothing discovered", ["seed", D], env={"FAKE_SECRETS": ""})
    yield case(
        "seed: discovery reauth", ["seed", D], env={"FAKE_REAUTH_ON": "secrets list"}
    )
    yield case(
        "seed: version list failure",
        ["seed", D, "ALPHA_KEY"],
        env={"FAKE_FAIL_ON": "versions list"},
    )
    yield case(
        "seed: add fails",
        ["seed", D, "ALPHA_KEY", "BETA_KEY"],
        stdin=b"x\ny\n",
        env={"FAKE_ADD_FAIL": "1"},
    )
    yield case("seed: unknown flag", ["seed", D, "--rotate"])
    yield case("seed: lone dash is a flag", ["seed", D, "-"])
    yield case("no subcommand", [])
    yield case("empty subcommand", [""])
    yield case("no infra dir", ["status"])
    yield case("empty infra dir", ["seed", ""])
    yield case("unknown subcommand", ["bogus", D])
    yield case("unknown subcommand, unmapped dir", ["bogus", "not/mapped"])
    yield case("unmapped dir", ["status", "not/in/the/map"])
    yield case("reference row is not a dir", ["status", "-"])
    yield case("project '-'", ["status", "dash/infra"])
    yield case("project missing", ["status", "noproj/infra"])
    yield case(
        "map missing", ["status", D], env={"GCP_IDENTITY_MAP": "{root}/nope.tsv"}
    )
    yield case(
        "resolver missing",
        ["status", D],
        env={"GCP_IDENTITY_RESOLVER": "{root}/nope.sh"},
    )
    yield case(
        "map is a directory", ["status", D], env={"GCP_IDENTITY_MAP": "{root}/log"}
    )
    yield case("gcloud missing", ["status", D], env={"GCLOUD_BIN": "{root}/no-gcloud"})
    yield case(
        "default map under BUILD_WORKSPACE_DIRECTORY",
        ["status", D],
        env={"GCP_IDENTITY_MAP": None, "BUILD_WORKSPACE_DIRECTORY": "{root}"},
    )


def main():
    global RESOLVER
    RESOLVER = os.path.abspath(need_env("RESOLVE_IDENTITY"))
    h = Harness(
        "gcp-secrets parity", need_env("GCP_SECRETS_SH"), need_env("GCP_SECRETS_RS")
    )
    for c in cases():
        h.check(c)
    return h.finish()


RESOLVER = ""

if __name__ == "__main__":
    sys.exit(main())
