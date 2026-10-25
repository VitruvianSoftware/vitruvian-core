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
"""gcp-token, the Rust port, against gcp-token.sh: same exit code, stdout,
stderr, and the same calls to gcloud, pulumi and ssh (argv, plus whether
CLOUDSDK_AUTH_ACCESS_TOKEN reached them), and the same broker cache left
behind, on every case below.

    bazel test //tools/gcp-token:gcp_token_rs_parity_test
"""

import os
import sys

sys.path.insert(
    0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shell-compat")
)
from parity_harness import Case, Harness, need_env, write, write_exec  # noqa: E402

LOCAL = "ya29.local-" + "L" * 60
BROKER = "ya29.broker-" + "B" * 60
ESC = "ya29.esc-" + "E" * 60
ACCOUNT = "james@vitruviansoftware.dev"

GCLOUD = r"""#!/usr/bin/env bash
printf '%s | CLOUDSDK=%s\n' "$*" "${CLOUDSDK_AUTH_ACCESS_TOKEN-<unset>}" >>"$LOGDIR/gcloud.log"
case "${FAKE_GCLOUD:-none}" in
  have)    echo "$LOCAL_TOKEN"; exit 0 ;;
  ambient) [ -n "${CLOUDSDK_AUTH_ACCESS_TOKEN:-}" ] && { printf '%s' "$CLOUDSDK_AUTH_ACCESS_TOKEN"; exit 0; }
           echo "ERROR: no credentials" >&2; exit 1 ;;
  short)   echo "tiny"; exit 0 ;;
  failtok) echo "$LOCAL_TOKEN"; exit 3 ;;
  crlf)    printf '%s\r\n' "$LOCAL_TOKEN"; exit 0 ;;
  noisy)   echo "WARNING: something" >&2; echo "$LOCAL_TOKEN"; exit 0 ;;
  *)       echo "ERROR: (gcloud.auth.print-access-token) no credentials" >&2; exit 1 ;;
esac
"""

SSH = r"""#!/usr/bin/env bash
printf '%s\n' "$*" >>"$LOGDIR/ssh.log"
printf 'CLOUDSDK=%s\n' "${CLOUDSDK_AUTH_ACCESS_TOKEN-<unset>}" >>"$LOGDIR/ssh.log"
target=""
for a in "$@"; do case "$a" in *@*) case "$a" in *" "*) ;; *) target="${a#*@}" ;; esac ;; esac; done
case "$target" in
  nogcloud) echo "gcloud: command not found" >&2; exit 127 ;;
  nosuch)   echo "bash: /x/gcloud: No such file or directory" >&2; exit 127 ;;
  nologin)  echo "ERROR: (gcloud.auth.print-access-token) Your current active account [x] does not have any valid credentials" >&2; exit 1 ;;
  notvalid) echo "ERROR: x is not a valid account" >&2; exit 1 ;;
  reauth)   echo "ERROR: (gcloud.auth.print-access-token) There was a problem refreshing your current auth tokens: Reauthentication failed. cannot prompt during non-interactive execution." >&2; exit 1 ;;
  down)     echo "ssh: connect to host: Connection timed out" >&2; exit 255 ;;
  refused)  echo "ssh: connect to host x port 22: Connection refused" >&2; exit 255 ;;
  hostkey)  echo "Host key verification failed." >&2; exit 255 ;;
  denied)   echo "james@x: Permission denied (publickey)." >&2; exit 255 ;;
  good)     echo "$BROKER_TOKEN"; exit 0 ;;
  crlf)     printf '%s\r\n' "$BROKER_TOKEN"; exit 0 ;;
  junk)     echo "not-a-token"; exit 0 ;;
  silent)   exit 1 ;;
  multi)    printf 'first problem\nsecond problem\n' >&2; exit 1 ;;
  goodnoisy) echo "Warning: Permanently added 'x' to known hosts" >&2; echo "$BROKER_TOKEN"; exit 0 ;;
  *)        echo "ssh: Could not resolve hostname $target" >&2; exit 255 ;;
esac
"""

PULUMI = r"""#!/usr/bin/env bash
printf '%s | CLOUDSDK=%s\n' "$*" "${CLOUDSDK_AUTH_ACCESS_TOKEN-<unset>}" >>"$LOGDIR/pulumi.log"
[ "$1" = env ] && [ "$2" = get ] && exit 0
case "${FAKE_PULUMI:-ok}" in
  ok)     [ "$2" = open ] && { echo "$ESC_TOKEN"; exit 0; } ;;
  crlf)   [ "$2" = open ] && { printf '%s\r\n' "$ESC_TOKEN"; exit 0; } ;;
  short)  [ "$2" = open ] && { echo "tiny"; exit 0; } ;;
  failtok) echo "$ESC_TOKEN"; echo "error: partial" >&2; exit 1 ;;
  multi)  printf 'error: line one\nerror: line two\n' >&2; exit 1 ;;
  noerr)  exit 1 ;;
esac
echo "error: could not open environment" >&2
exit 1
"""


def setup_factory(cache=None, cache_dir=False, extra=None):
    def setup(root):
        write_exec(root + "/bin/gcloud", GCLOUD)
        write_exec(root + "/bin/ssh", SSH)
        write_exec(root + "/bin/pulumi", PULUMI)
        os.makedirs(root + "/log")
        if cache_dir:
            os.makedirs(root + "/cache/gcp-broker")
        elif cache is not None:
            write(root + "/cache/gcp-broker", cache)
        if extra:
            extra(root)

    return setup


BASE_ENV = {
    "LOGDIR": "{root}/log",
    "LOCAL_TOKEN": LOCAL,
    "BROKER_TOKEN": BROKER,
    "ESC_TOKEN": ESC,
    "VITRUVIAN_GCP_BROKER_CACHE": "{root}/cache/gcp-broker",
    "VITRUVIAN_GCP_BROKER": "good",
}


def case(name, args=None, env=None, setup=None, **kw):
    e = dict(BASE_ENV)
    e.update(env or {})
    return Case(
        name=name,
        args=[ACCOUNT] if args is None else args,
        env=e,
        setup=setup or setup_factory(),
        **kw,
    )


def cases():
    yield case("local credentials win", env={"FAKE_GCLOUD": "have"})
    yield case(
        "local token with CRLF is cleaned by $(...) only", env={"FAKE_GCLOUD": "crlf"}
    )
    yield case("local stderr noise is dropped", env={"FAKE_GCLOUD": "noisy"})
    yield case("local short token falls through", env={"FAKE_GCLOUD": "short"})
    yield case(
        "local token with a failing exit falls through", env={"FAKE_GCLOUD": "failtok"}
    )
    yield case("no local credentials: broker", env={"FAKE_GCLOUD": "none"})
    yield case("no gcloud at all: broker", env={"GCLOUD_BIN": "{root}/missing-gcloud"})
    yield case(
        "placeholder ambient token is dropped",
        env={"FAKE_GCLOUD": "ambient", "CLOUDSDK_AUTH_ACCESS_TOKEN": "proxy-injected"},
    )
    yield case(
        "real ambient token wins",
        env={
            "FAKE_GCLOUD": "ambient",
            "CLOUDSDK_AUTH_ACCESS_TOKEN": "ya29." + "R" * 80,
        },
    )
    yield case(
        "placeholder kept when gcloud is absent",
        env={
            "GCLOUD_BIN": "nope-gcloud",
            "CLOUDSDK_AUTH_ACCESS_TOKEN": "proxy-injected",
        },
    )
    yield case(
        "failover walks to the good node",
        env={"VITRUVIAN_GCP_BROKERS": "nogcloud,nologin,reauth,good"},
    )
    yield case(
        "every failure class is reported",
        env={
            "VITRUVIAN_GCP_BROKERS": "nogcloud,nosuch,nologin,notvalid,reauth,down,refused,hostkey,denied,junk,silent,multi,unknownhost"
        },
    )
    yield case(
        "default broker list",
        env={"VITRUVIAN_GCP_BROKER": "", "VITRUVIAN_GCP_BROKERS": ""},
    )
    yield case(
        "broker user override",
        env={"VITRUVIAN_GCP_BROKER_USER": "bob", "VITRUVIAN_GCP_BROKERS": "down,good"},
    )
    yield case("broker CRLF reply", env={"VITRUVIAN_GCP_BROKER": "crlf"})
    yield case(
        "broker stderr noise with a token", env={"VITRUVIAN_GCP_BROKER": "goodnoisy"}
    )
    yield case("broker junk reply is fatal", env={"VITRUVIAN_GCP_BROKER": "junk"})
    yield case("broker down is fatal", env={"VITRUVIAN_GCP_BROKER": "down"})
    yield case(
        "cached winner tried first",
        env={"VITRUVIAN_GCP_BROKERS": "nogcloud,good"},
        setup=setup_factory(cache="good\n"),
    )
    yield case(
        "cache with whitespace",
        env={"VITRUVIAN_GCP_BROKERS": "nogcloud,good"},
        setup=setup_factory(cache=" go\tod \n\n"),
    )
    yield case(
        "stale cached host ignored",
        env={"VITRUVIAN_GCP_BROKERS": "nogcloud,good"},
        setup=setup_factory(cache="ghost\n"),
    )
    yield case(
        "empty cache file",
        env={"VITRUVIAN_GCP_BROKERS": "nogcloud,good"},
        setup=setup_factory(cache=""),
    )
    yield case(
        "cache path is a directory",
        env={"VITRUVIAN_GCP_BROKERS": "nogcloud,good"},
        setup=setup_factory(cache_dir=True),
    )
    yield case(
        "cache dir created under a new parent",
        env={
            "VITRUVIAN_GCP_BROKER_CACHE": "{root}/deep/er/cache",
            "VITRUVIAN_GCP_BROKERS": "down,good",
        },
    )
    yield case("cache in HOME by default", env={"VITRUVIAN_GCP_BROKER_CACHE": None})
    yield case(
        "spaces in the broker list",
        env={"VITRUVIAN_GCP_BROKERS": "down, good"},
        setup=setup_factory(cache="good\n"),
    )
    yield case(
        "empty element in the broker list", env={"VITRUVIAN_GCP_BROKERS": "down,,good"}
    )
    yield case("ESC mints", env={"VITRUVIAN_ESC_ENV": "proj/env"})
    yield case(
        "ESC CRLF token", env={"VITRUVIAN_ESC_ENV": "proj/env", "FAKE_PULUMI": "crlf"}
    )
    yield case(
        "ESC custom path",
        env={"VITRUVIAN_ESC_ENV": "proj/env", "VITRUVIAN_ESC_PATH": "x.y"},
    )
    yield case(
        "ESC broken falls back",
        env={"VITRUVIAN_ESC_ENV": "proj/env", "FAKE_PULUMI": "broken"},
    )
    yield case(
        "ESC short falls back",
        env={"VITRUVIAN_ESC_ENV": "proj/env", "FAKE_PULUMI": "short"},
    )
    yield case(
        "ESC token with failure falls back",
        env={"VITRUVIAN_ESC_ENV": "proj/env", "FAKE_PULUMI": "failtok"},
    )
    yield case(
        "ESC multi-line error",
        env={"VITRUVIAN_ESC_ENV": "proj/env", "FAKE_PULUMI": "multi"},
    )
    yield case(
        "ESC silent failure",
        env={"VITRUVIAN_ESC_ENV": "proj/env", "FAKE_PULUMI": "noerr"},
    )
    yield case(
        "ESC with no pulumi installed",
        env={"VITRUVIAN_ESC_ENV": "proj/env", "PULUMI_BIN": "no-pulumi"},
    )
    yield case(
        "local beats ESC", env={"VITRUVIAN_ESC_ENV": "proj/env", "FAKE_GCLOUD": "have"}
    )
    yield case(
        "ESC sees the ambient placeholder removed",
        env={"VITRUVIAN_ESC_ENV": "proj/env", "CLOUDSDK_AUTH_ACCESS_TOKEN": "short"},
    )
    yield case("no account", args=[])
    yield case("empty account", args=[""])
    yield case("metacharacter account", args=["james@x.dev; touch {root}/pwned"])
    yield case("not an email", args=["not-an-email"])
    yield case("missing dot", args=["a@bc"])
    yield case("leading @", args=["@b.c"])
    yield case("tab in account", args=["james@x.dev\t"])
    yield case("trailing newline in account", args=["james@x.dev\n"])
    yield case("newline mid account", args=["james@x\n.dev"])
    yield case("many bad bytes", args=["a@b.c" + ";" * 40 + "!$&"])
    yield case("control bytes", args=["a@b.c\x01\x7f\r"])
    yield case(
        "valid addresses", args=["user+tag@example.co.uk"], env={"FAKE_GCLOUD": "have"}
    )
    yield case(
        "service account address",
        args=["sa-x@prj-c-3d09.iam.gserviceaccount.com"],
        env={"FAKE_GCLOUD": "have"},
    )
    yield case(
        "extra args ignored", args=[ACCOUNT, "extra"], env={"FAKE_GCLOUD": "have"}
    )
    yield case(
        "MIN_TOKEN_LEN lowered", env={"MIN_TOKEN_LEN": "3", "FAKE_GCLOUD": "short"}
    )
    yield case(
        "MIN_TOKEN_LEN raised",
        env={"MIN_TOKEN_LEN": "500", "VITRUVIAN_GCP_BROKERS": "good"},
    )
    yield case("no ssh", env={"SSH_BIN": "{root}/no-ssh"})
    yield case("ssh by name on PATH", env={"SSH_BIN": "ssh"})


def main():
    h = Harness(
        "gcp-token parity",
        need_env("GCP_TOKEN_SH"),
        need_env("GCP_TOKEN_RS"),
    )
    for c in cases():
        h.check(c)
    return h.finish()


if __name__ == "__main__":
    sys.exit(main())
