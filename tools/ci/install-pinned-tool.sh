#!/usr/bin/env bash
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

# install-pinned-tool.sh — download a pinned CI-tool release asset, verify its
# checksum, and install it to ~/.local/bin for the rest of the job to use.
#
# Extracted from 4 near-identical "install <tool> (pinned + checksum-verified)"
# steps that had drifted into copy-pasted duplication:
#   actionlint.yaml       (tar.gz, actionlint)
#   gitops-validate.yaml  (tar.gz, kubeconform)
#   supply-chain.yaml     (raw binary, osv-scanner)
#   mcp-slack-image.yaml  (raw binary, osv-scanner — its own comment already
#                          admitted "same shape and same version pin as
#                          supply-chain.yaml's install step" but never deduped)
# All four fetch a binary asset + a checksums listing with the same curl retry
# policy, verify with `grep <pattern> <checksums> | sha256sum -c -`, install to
# ~/.local/bin, and add that dir to $GITHUB_PATH. Centralizing means a curl/
# retry/verification fix lands once instead of drifting across N near-copies.
#
# Usage:
#   install-pinned-tool.sh <base-url> <asset> <checksum-file> <checksum-pattern> <bin-name> --tar|--raw [member-path]
#
#   <base-url>         release base URL, e.g.
#                       https://github.com/rhysd/actionlint/releases/download/v1.7.7
#   <asset>             release asset filename to download from <base-url>, e.g.
#                       actionlint_1.7.7_linux_amd64.tar.gz
#   <checksum-file>     checksum-listing asset filename to download from
#                       <base-url>, e.g. actionlint_1.7.7_checksums.txt
#   <checksum-pattern>  grep pattern (basic regex, passed to plain `grep`, not
#                       `grep -F`) that selects <asset>'s line out of
#                       <checksum-file> for `sha256sum -c`. Callers that need an
#                       anchored match (e.g. to avoid a shorter asset name
#                       matching as a substring of a longer one) pass their own
#                       anchors, same as the pre-extraction call sites did.
#   <bin-name>          installed binary name in ~/.local/bin. In --tar mode
#                       this is ALSO the member name extracted from the archive
#                       (true for both tar.gz call sites today: actionlint and
#                       kubeconform both name the in-archive binary the same as
#                       the tool).
#   --tar               <asset> is a .tar.gz; extract member <bin-name> from it.
#   --raw               <asset> IS the binary; install it directly as <bin-name>.
#   [member-path]       OPTIONAL, --tar only. Path of the binary INSIDE the
#                       archive when it is not a top-level member named
#                       <bin-name>. Prometheus ships promtool as
#                       prometheus-<ver>.linux-amd64/promtool, so the plain
#                       member form cannot find it. Leading directories are
#                       stripped so the binary still lands at
#                       ~/.local/bin/<bin-name>. Defaults to <bin-name>, which
#                       is what every pre-existing call site relies on.
#
# Every fetch uses --retry 3 --retry-delay 2 --retry-all-errors --max-time 120:
# several call sites are REQUIRED merge-queue checks, so one transient
# GitHub-releases blip must not redden the queue for a reason unrelated to the
# change under test.
#
# Downloads into a private mktemp -d (not the checkout root the original
# inline steps used) so there is nothing to `rm -f` afterward and no risk of a
# stray asset file leaking into a later step's working tree.
#
# Appends ~/.local/bin to $GITHUB_PATH — this script is meant to run as a
# GitHub Actions step, not standalone; GITHUB_PATH must already be set.

set -euo pipefail

if [ "$#" -lt 6 ] || [ "$#" -gt 7 ]; then
  echo "usage: install-pinned-tool.sh <base-url> <asset> <checksum-file> <checksum-pattern> <bin-name> --tar|--raw [member-path]" >&2
  exit 2
fi

BASE_URL="$1"
ASSET="$2"
CHECKSUM_FILE="$3"
CHECKSUM_PATTERN="$4"
BIN_NAME="$5"
MODE="$6"

MEMBER_PATH="${7:-${BIN_NAME}}"

case "${MODE}" in
  --tar | --raw) ;;
  *)
    echo "install-pinned-tool: mode must be --tar or --raw, got '${MODE}'" >&2
    exit 2
    ;;
esac

: "${GITHUB_PATH:?GITHUB_PATH must be set — this script is meant to run as a GitHub Actions step}"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
cd "${work}"

curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors --max-time 120 -O "${BASE_URL}/${ASSET}"
curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors --max-time 120 -O "${BASE_URL}/${CHECKSUM_FILE}"

# NB: this pipes INTO `sha256sum -c -`, which reads its ENTIRE stdin rather
# than exiting early like `grep -q` does — so there is no SIGPIPE race here.
# (tools/license/verify.sh has the full incident writeup for the `grep -q`
# version of this pattern: a `grep -q` consumer exits the instant it matches,
# and if the producer is still writing when that happens the producer takes
# SIGPIPE and the pipeline reports 141 under `pipefail`, even though the match
# was genuinely found.) Do not change the consumer here to `grep -q`.
grep "${CHECKSUM_PATTERN}" "${CHECKSUM_FILE}" | sha256sum -c -

mkdir -p "${HOME}/.local/bin"
case "${MODE}" in
  --tar)
    # strip-components = the member's directory depth, so a nested binary still
    # lands as ~/.local/bin/<bin-name> rather than recreating the archive tree.
    _depth="$(printf '%s' "${MEMBER_PATH}" | awk -F/ '{print NF-1}')"
    tar -xzf "${ASSET}" -C "${HOME}/.local/bin" \
      --strip-components="${_depth}" "${MEMBER_PATH}"
    ;;
  --raw)
    install -m 0755 "${ASSET}" "${HOME}/.local/bin/${BIN_NAME}"
    ;;
esac

echo "${HOME}/.local/bin" >> "${GITHUB_PATH}"
echo "install-pinned-tool: installed ${BIN_NAME} from ${BASE_URL}/${ASSET}"
