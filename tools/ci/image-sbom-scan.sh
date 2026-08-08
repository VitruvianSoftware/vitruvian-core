#!/usr/bin/env bash
#
# Scan a PUBLISHED image's SBOM attestation for known advisories.
#
# WHY THIS EXISTS, and why `osv-scan` does not already cover it (#1503).
#
# `osv-scan` (required) reads the repo's committed LOCKFILES. The mcp-slack image
# does not install from them: mcp-slack/Dockerfile installs with
# `pnpm install --prod --no-frozen-lockfile` inside a standalone Docker context,
# which explicitly permits a different resolution. So nothing PINS the image's
# dependency tree to the scanned tree, and until now nothing SCANNED the image's
# tree. Measured at digest sha256:63912eee... on 2026-08-08: the image resolved
# `jose@6.2.8` where the repo lockfile pins a different patch. Real drift, no
# advisory that day -- the defect is the property, not a specific bad version.
#
# TWO ARMS, AND ONLY ONE BLOCKS. This is deliberate and is the difference between
# a gate that survives and one that gets switched off in a week:
#
#   BLOCKING  packages under APP_PREFIX (/app/node_modules) -- the application's
#             own dependency tree, the thing `osv-scan` cannot see. Clean at the
#             first measurement (0 of 93 packages carried an advisory), so a red
#             here means a real change, not a pre-existing backlog.
#   REPORTING everything else -- the Debian base layer (node:*-slim, 39 advisory
#             instances at first measurement, mostly unfixed upstream) and the
#             build tooling left in the runtime layer. Blocking on these would be
#             red on arrival for reasons no PR author can fix.
#
# FAILS CLOSED, in three places, because every one of them is a way this check
# could go permanently green while asserting nothing:
#
#   1. no SPDX attestation on the index      -> exit 1. #1504 attaches one; if a
#      future edit drops `--sbom=true`, the scan must refuse rather than find
#      nothing to scan. "No SBOM" and "clean SBOM" are not the same result.
#   2. APP_PREFIX matches ZERO packages      -> exit 1. This is the built-in
#      positive control. The image really does have ~93 packages under
#      /app/node_modules; a filter that selects none would make the blocking arm
#      pass forever, and it would look identical to a clean tree.
#   3. osv-scanner missing or non-runnable   -> exit 1. An absent scanner emits
#      empty JSON that parses cleanly to "no advisories".
#
# Anonymous registry access throughout: no credential, same path the cluster
# uses. Run it locally against any published digest:
#
#   IMAGE=ghcr.io/vitruviansoftware/mcp-slack \
#   DIGEST=sha256:63912eee... bash tools/ci/image-sbom-scan.sh
#
set -euo pipefail

: "${IMAGE:?IMAGE is required (e.g. ghcr.io/vitruviansoftware/mcp-slack)}"
: "${DIGEST:?DIGEST is required (the INDEX digest, sha256:...)}"
APP_PREFIX="${APP_PREFIX:-/app/node_modules}"

# The index digest, not a platform manifest: the attestations hang off the index
# and the chart pins the index (mcp-slack/deploy/chart/templates/_helpers.tpl,
# `mcp-slack.imageRef`). A platform digest here would find no attestations at
# all, which arm 1 above turns into a refusal rather than a green.
case "${DIGEST}" in
  sha256:*) ;;
  *) echo "::error::DIGEST must be a sha256:... reference, got '${DIGEST}'" >&2; exit 1 ;;
esac

for bin in curl jq osv-scanner; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "::error::${bin} not found on PATH." >&2
    [ "$bin" = osv-scanner ] && echo "Locally: go install github.com/google/osv-scanner/v2/cmd/osv-scanner@v2.4.0" >&2
    exit 1
  }
done

REGISTRY="${IMAGE%%/*}"
REPOSITORY="${IMAGE#*/}"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

echo "==> anonymous pull token for ${REPOSITORY} on ${REGISTRY}"
TOKEN="$(curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors --max-time 60 \
  "https://${REGISTRY}/token?scope=repository:${REPOSITORY}:pull&service=${REGISTRY}" \
  | jq -r '.token // empty')"
[ -n "${TOKEN}" ] || { echo "::error::no anonymous pull token for ${IMAGE} -- is the package public?" >&2; exit 1; }

fetch() { # fetch <digest-or-ref> <accept> <out>
  curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors --max-time 120 \
    -H "Authorization: Bearer ${TOKEN}" -H "Accept: $2" \
    "https://${REGISTRY}/v2/${REPOSITORY}/manifests/$1" -o "$3"
}

# Accept BOTH the index and the single-manifest media type, then check which one
# came back. Sending only the index type makes the registry answer a platform
# digest with something curl aborts on (exit 56), which fails closed but reports
# a transport error for what is really "you passed the wrong kind of digest".
# Fail closed AND say why.
echo "==> index ${DIGEST}"
fetch "${DIGEST}" \
  'application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json' \
  "${WORK}/index.json"
if [ "$(jq -r '.manifests | length? // 0' "${WORK}/index.json" 2>/dev/null || echo 0)" = "0" ]; then
  echo "::error::${DIGEST} is not an image index (mediaType: $(jq -r '.mediaType // "unknown"' "${WORK}/index.json"))." >&2
  echo "::error::Pass the INDEX digest -- attestations hang off the index, and the chart pins the index." >&2
  exit 1
fi

# Attestation manifests are the unknown/unknown entries buildx adds beside each
# platform manifest, linked by vnd.docker.reference.digest.
#
# Written to a FILE and read back with a redirect, not piped into the loop: a
# `cmd | while read` body runs in a subshell, so a failure recorded inside it is
# discarded and the script exits 0. Nearly shipped that inside a fix for a
# silently-green bug once already. `mapfile` would also do, but it is bash 4+ and
# this has to be runnable on a stock macOS bash 3.2.
jq -r '
  .manifests[]? | select(.annotations["vnd.docker.reference.type"] == "attestation-manifest")
  | "\(.digest) \(.annotations["vnd.docker.reference.digest"])"' \
  "${WORK}/index.json" > "${WORK}/attestations.txt"
[ -s "${WORK}/attestations.txt" ] || {
  echo "::error::${IMAGE}@${DIGEST} carries no attestation manifests." >&2
  echo "::error::Is this an index digest? A platform manifest has none." >&2
  exit 1
}

BLOCKING_RC=0
SBOMS_FOUND=0
SUMMARY="${WORK}/summary.md"
: > "${SUMMARY}"

while read -r att_digest subject; do
  [ -n "${att_digest}" ] || continue
  echo "==> attestation ${att_digest} (subject ${subject})"
  fetch "${att_digest}" 'application/vnd.oci.image.manifest.v1+json' "${WORK}/att.json"

  spdx_layer="$(jq -r '
    .layers[]? | select(.annotations["in-toto.io/predicate-type"] == "https://spdx.dev/Document")
    | .digest' "${WORK}/att.json" | head -1)"
  if [ -z "${spdx_layer}" ]; then
    # Deliberately not `continue`: an index whose provenance is present but whose
    # SBOM is absent is exactly the state #1504 fixed, and it must not read as a
    # pass. See fail-closed reason 1 in the header.
    echo "::error::attestation ${att_digest} has no https://spdx.dev/Document predicate" >&2
    echo "::error::(provenance alone is not an SBOM -- has --sbom=true been dropped from the build?)" >&2
    exit 1
  fi
  SBOMS_FOUND=$((SBOMS_FOUND + 1))

  # The extractor selects on the FILENAME, so the .spdx.json suffix is load-bearing.
  full="${WORK}/${subject#sha256:}.spdx.json"
  curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors --max-time 300 \
    -H "Authorization: Bearer ${TOKEN}" \
    "https://${REGISTRY}/v2/${REPOSITORY}/blobs/${spdx_layer}" | jq '.predicate' > "${full}"

  total="$(jq -r '.packages | length' "${full}")"

  # Arm 1 (blocking): the application's own tree, identified by where each
  # package's manifest actually lives in the image, not by name heuristics.
  app="${WORK}/${subject#sha256:}.app.spdx.json"
  jq --arg p "${APP_PREFIX}" '
    .packages = [.packages[] | select((.sourceInfo // "") | contains($p))]
    | .relationships = []
    | .files = []' "${full}" > "${app}"
  app_count="$(jq -r '.packages | length' "${app}")"

  echo "    ${total} packages total, ${app_count} under ${APP_PREFIX}"
  if [ "${app_count}" -eq 0 ]; then
    echo "::error::zero packages under ${APP_PREFIX} in ${subject} -- the blocking arm would pass vacuously." >&2
    echo "::error::Either the image layout changed or the filter is wrong. Refusing rather than reporting clean." >&2
    exit 1
  fi

  echo "--> BLOCKING scan: ${APP_PREFIX} (${app_count} packages)"
  if osv-scanner scan source --sbom="${app}" --format table; then
    echo "    no advisories in the application dependency tree"
  else
    echo "::error::advisories found under ${APP_PREFIX} for ${subject}." >&2
    echo "::error::At the default prefix this is the application's OWN dependency tree -- the one" >&2
    echo "::error::osv-scan cannot see, because the image does not install from the committed lockfile." >&2
    BLOCKING_RC=1
  fi

  echo "--> REPORTING scan: whole image (${total} packages)"
  # `|| true`: this arm never blocks. Its exit code is information, not a verdict.
  osv-scanner scan source --sbom="${full}" --format markdown > "${WORK}/report.md" 2>/dev/null || true
  {
    echo "### Image SBOM — \`${subject}\`"
    echo
    echo "\`${total}\` packages, \`${app_count}\` under \`${APP_PREFIX}\` (the blocking arm)."
    echo
    echo "<details><summary>Full advisory report (reporting only — does not block)</summary>"
    echo
    cat "${WORK}/report.md"
    echo
    echo "</details>"
    echo
  } >> "${SUMMARY}"
done < "${WORK}/attestations.txt"

echo "==> ${SBOMS_FOUND} SBOM attestation(s) scanned"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "${SUMMARY}" >> "${GITHUB_STEP_SUMMARY}"
else
  cat "${SUMMARY}"
fi

exit "${BLOCKING_RC}"
