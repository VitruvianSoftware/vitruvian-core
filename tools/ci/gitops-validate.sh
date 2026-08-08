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

# gitops-validate.sh — schema + syntax validation for the ArgoCD GitOps tree
# BEFORE it reaches main and reconciles live against the cluster (issue #454).
#
# gitops/** is a closed GitOps loop: ArgoCD selfHeal applies whatever lands on
# main, and the app-of-platform root PRUNES. Nothing validated these manifests
# in CI, so a malformed Application/ApplicationSet (wrong kind/apiVersion, a
# duplicate key, a missing required field) could reconcile live. This runs
# kubeconform over every manifest under gitops/argocd.
#
# Scope / known limitation: this validates manifest SCHEMA + SYNTAX. It does NOT
# expand ApplicationSet generators (that needs the applicationset controller /
# a cluster), so the goTemplate-brace class of render bug is a follow-up. Even
# so, this catches wrong kinds, bad apiVersions, duplicate keys, and malformed
# resources — the highest-frequency failures.
#
# Requires: kubeconform on PATH (the workflow installs a pinned release).

set -euo pipefail

REPO="${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "${REPO}"

# --- 1. goTemplate render simulation (the failure class kubeconform cannot see)
#
# kubeconform below validates the STATIC yaml. It never expands an
# ApplicationSet, so a goTemplate that the controller cannot render passes it
# clean and then reconciles live (app-of-platform PRUNES). That is not
# hypothetical: issue #414 was a literal backtick closing the prometheus
# values-block raw-string early, which broke rendering of the whole appset.
#
# tools/gitops/appset_render parses every appset with the SAME engine the
# ApplicationSet controller uses (Go text/template + sprig names, under
# `missingkey=zero`), so it agrees with the controller by construction. It is
# pure CPU: no network, no cluster, no helm -- deliberately NOT `helm template`,
# because all 26 chart sources here are remote and rendering them all is what
# OOM-killed the argocd repo-server (#422).
#
# Runs FIRST: a template that cannot render makes the kubeconform result below
# moot, and this failure is far cheaper to diagnose.
#
# Deliberately BEFORE the kubeconform guard below: this check needs neither
# kubeconform nor network, so an operator can run it locally with nothing
# installed -- which is the point of CONTRIBUTING.md:419's "simulate-render
# before merge". Gating it behind a kubeconform lookup would have made the
# cheapest, most-needed check the hardest one to run.
echo "gitops-validate: simulating ApplicationSet goTemplate rendering ..."
GOWORK=off go run ./tools/gitops/appset_render -root gitops/argocd

# --- 2. Schema validation of the static manifests. ---------------------------
if ! command -v kubeconform >/dev/null 2>&1; then
  echo "gitops-validate: kubeconform not found on PATH" >&2
  exit 1
fi

# Overridable so a cold run can be exercised without blowing away a developer's
# warm /tmp cache (the CI runner starts cold either way).
SCHEMA_DIR="${SCHEMA_DIR:-/tmp/k8s-json-schema}"
CRD_CATALOG_DIR="${CRD_CATALOG_DIR:-/tmp/crd-catalog}"

# Only the ONE subdirectory the -schema-location below actually reads. The
# kubernetes-json-schema repo carries a full schema set per k8s release, so a
# plain `git clone --depth 1` checks out 1,173,365 files and took 87s of a ~100s
# job -- the slowest required check in the merge queue, paid on every PR, every
# push to main, and every merge_group entry, to read 1,505 of those files.
# `--filter=blob:none --sparse` + this cone cuts that to ~6s with a byte-identical
# kubeconform summary (verified: 102 resources, Valid 101, Skipped 1, both before
# and after). Caching would be WORSE than sparse here: the tree is 197MB, so
# tar/untar of the cache costs more than the sparse clone it replaces.
SCHEMA_CONE="master-standalone-strict"

# clone_shallow <url> <dest> [sparse-cone]
#
# --retry equivalent for `git clone`, which has no retry flag of its own. This
# is a REQUIRED merge-queue check whose only remote dependencies are these two
# clones, so a single transient GitHub blip reddens the queue for a reason
# unrelated to the change under test -- the same failure mode #1349 fixed for the
# curl-based tool downloads in the other required checks, missed here because the
# fetch lives in this script rather than in the workflow yaml.
clone_shallow() {
  url="$1"; dest="$2"; cone="${3:-}"
  attempt=1
  while [ "${attempt}" -le 3 ]; do
    rm -rf "${dest}"
    if [ -n "${cone}" ]; then
      git clone --depth 1 --filter=blob:none --sparse "${url}" "${dest}" \
        && git -C "${dest}" sparse-checkout set "${cone}" \
        && return 0
    else
      git clone --depth 1 "${url}" "${dest}" && return 0
    fi
    echo "gitops-validate: clone of ${url} failed (attempt ${attempt}/3), retrying..." >&2
    attempt=$((attempt + 1))
    sleep 5
  done
  echo "gitops-validate: giving up cloning ${url} after 3 attempts" >&2
  return 1
}

# Re-clone when the cone is absent as well as when the dir is: a leftover tree
# from an older (non-sparse, or differently-coned) local run would otherwise be
# reused and silently resolve no schemas -- see the probe below for why that
# matters.
if [ ! -d "${SCHEMA_DIR}/${SCHEMA_CONE}" ]; then
  echo "gitops-validate: cloning kubernetes-json-schema (sparse: ${SCHEMA_CONE})..."
  clone_shallow https://github.com/yannh/kubernetes-json-schema.git "${SCHEMA_DIR}" "${SCHEMA_CONE}" || exit 1
fi

# CRD schemas the k8s-core set doesn't cover (ArgoCD, Gateway API, cert-manager,
# external-dns DNSEndpoint, sealed-secrets, Envoy Gateway, …). Read across ALL
# groups, so there is no cone to narrow to -- and at ~7s it isn't worth one.
if [ ! -d "${CRD_CATALOG_DIR}" ]; then
  echo "gitops-validate: cloning CRDs-catalog..."
  clone_shallow https://github.com/datreeio/CRDs-catalog.git "${CRD_CATALOG_DIR}" || exit 1
fi

# --- Guard: prove both schema trees actually resolve. ------------------------
#
# `-ignore-missing-schemas` (needed for CRDs genuinely absent from the catalog,
# e.g. Cilium and k3s) means kubeconform treats an UNRESOLVABLE -schema-location
# exactly like an uncovered CRD: it SKIPS the resource and exits 0. So a wrong
# path, an upstream layout change, or a half-materialised clone degrades this
# required check into a green no-op that validates nothing -- silently. Measured:
# pointing -schema-location at /nonexistent yields
# "Valid: 0, Invalid: 0, Skipped: 1" and exit 0.
#
# Probe one known schema per source before trusting the run. Both are core,
# long-lived kinds already present in gitops/argocd, so neither probe is a
# maintenance burden that will rot.
for probe in \
  "${SCHEMA_DIR}/${SCHEMA_CONE}/deployment-apps-v1.json" \
  "${CRD_CATALOG_DIR}/argoproj.io/application_v1alpha1.json"
do
  if [ ! -f "${probe}" ]; then
    echo "gitops-validate: schema tree incomplete -- ${probe} is missing." >&2
    echo "gitops-validate: refusing to run, as -ignore-missing-schemas would" >&2
    echo "gitops-validate: turn the missing schemas into a silent pass." >&2
    exit 1
  fi
done

echo "gitops-validate: kubeconform over gitops/argocd ..."

# Only *.yaml manifests — NOT the Grafana dashboard .json files under
# platform/grafana-dashboards (those are configMapGenerator inputs, not k8s
# resources; kubeconform would reject them for a missing 'kind'), and NOT any
# values.yaml (a plain Helm values file, referenced via an ArgoCD multi-source
# `valueFiles` ref and/or an argocd-image-updater git write-back target --
# excluded from the owning Application's own directory-recurse render via
# `directory.exclude` for the same reason; see gitops/argocd/platform/buzz/).
#
# -strict                    reject duplicate keys + unknown fields.
# -ignore-missing-schemas    CRDs in neither schema source (e.g. Cilium, k3s)
#                            are skipped rather than failed -- see the guard
#                            above for why that flag needs one.
# -skip ImageUpdater         datreeio/CRDs-catalog's argocd-image-updater.
#                            argoproj.io schema is ahead of the chart version
#                            we actually pin (1.2.4 / appVersion v1.2.2):
#                            it demands a top-level `spec.namespace` the real,
#                            chart-shipped CRD (templates/crd-imageupdaters.yaml)
#                            has no such requirement for -- confirmed by
#                            pulling that exact template and diffing its
#                            `required:` list. A genuine schema/version
#                            mismatch, not a manifest bug; skip rather than
#                            let a third-party catalog lag fail a correct
#                            manifest.
SUMMARY="$(
  find gitops/argocd -name '*.yaml' -not -name 'values.yaml' -print0 \
    | xargs -0 kubeconform \
        -strict \
        -ignore-missing-schemas \
        -skip ImageUpdater \
        -schema-location "${SCHEMA_DIR}/${SCHEMA_CONE}/{{.ResourceKind}}{{.KindSuffix}}.json" \
        -schema-location "${CRD_CATALOG_DIR}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" \
        -summary
)" || { echo "${SUMMARY}"; exit 1; }
echo "${SUMMARY}"

# Second half of the same guard: the probes prove the trees exist, this proves
# they were USED. If every resource skipped, kubeconform validated nothing and
# still exited 0 -- a green check that checks nothing is worse than a red one.
VALID="$(printf '%s\n' "${SUMMARY}" | sed -n 's/.*Valid: \([0-9]*\).*/\1/p')"
if [ -z "${VALID}" ] || [ "${VALID}" -eq 0 ]; then
  echo "gitops-validate: no resource validated against a schema -- treating as" >&2
  echo "gitops-validate: a failure, not a pass. Check the -schema-location paths." >&2
  exit 1
fi

# --- 3. The .disabled manifests. ---------------------------------------------
#
# The find above globs '*.yaml', so a '*.yaml.disabled' manifest matches
# NOTHING and is validated by nothing. There are nine of them, and the
# consequence is the sharpest version of a shape this repo keeps producing: a
# .disabled file's FIRST automated check would arrive at the moment it is
# renamed to .yaml -- which is also the moment ArgoCD starts syncing it. The
# first execution and the irreversible step were the same event.
#
# Staying out of ArgoCD's sync is the whole point of the convention and is not
# in question here. But schema validation is not syncing: these are the exact
# bytes the rename promotes, so validating them costs nothing and moves the
# first check to before the decision instead of after it.
#
# COPIED to a temp tree with the suffix stripped rather than passed directly.
# kubeconform selects its parser by file extension, so handing it a
# '.yaml.disabled' path risks it declining to parse the file and SKIPPING it --
# which, with -ignore-missing-schemas, exits 0. That would have produced a
# validator that validates nothing while reporting green: the failure this whole
# section exists to remove, reintroduced by the fix for it.
DISABLED="$(find gitops/argocd -name '*.yaml.disabled' | sort)"
if [ -n "${DISABLED}" ]; then
  echo "gitops-validate: kubeconform over .disabled manifests ..."
  DISABLED_TMP="$(mktemp -d)"
  trap 'rm -rf "${DISABLED_TMP}"' EXIT
  for f in ${DISABLED}; do
    dest="${DISABLED_TMP}/${f#gitops/argocd/}"
    dest="${dest%.disabled}"
    mkdir -p "$(dirname "${dest}")"
    cp "${f}" "${dest}"
  done

  DISABLED_SUMMARY="$(
    find "${DISABLED_TMP}" -name '*.yaml' -not -name 'values.yaml' -print0 \
      | xargs -0 kubeconform \
          -strict \
          -ignore-missing-schemas \
          -skip ImageUpdater \
          -schema-location "${SCHEMA_DIR}/${SCHEMA_CONE}/{{.ResourceKind}}{{.KindSuffix}}.json" \
          -schema-location "${CRD_CATALOG_DIR}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" \
          -summary
  )" || { echo "${DISABLED_SUMMARY}"; exit 1; }
  echo "${DISABLED_SUMMARY}"

  # Stricter than the Valid > 0 guard used above, deliberately: assert
  # Skipped == 0.
  #
  # A SKIP is the specific silent failure this section exists to catch. With
  # -ignore-missing-schemas, a manifest kubeconform declines to parse -- the
  # exact risk the temp-copy addresses -- is skipped and the run still exits 0.
  # `Valid > 0` would be satisfied by eight of nine validating while the ninth
  # silently did nothing, and the ninth is the SealedSecret, whose CRD is the
  # one most likely to be absent from the catalog.
  #
  # Achievable rather than aspirational: measured Valid 9 / Skipped 0 across all
  # nine. So a skip appearing later is a real change -- a new CRD outside the
  # catalog, or a file kubeconform stopped parsing -- and should be looked at
  # rather than absorbed. Aegis's suggestion on #1502.
  DISABLED_COUNT="$(printf '%s\n' "${DISABLED}" | grep -c .)"
  DISABLED_VALID="$(printf '%s\n' "${DISABLED_SUMMARY}" | sed -n 's/.*Valid: \([0-9]*\).*/\1/p')"
  DISABLED_SKIPPED="$(printf '%s\n' "${DISABLED_SUMMARY}" | sed -n 's/.*Skipped: \([0-9]*\).*/\1/p')"
  if [ -z "${DISABLED_VALID}" ] || [ "${DISABLED_VALID}" -eq 0 ]; then
    echo "gitops-validate: found ${DISABLED_COUNT} .disabled manifest(s) but validated" >&2
    echo "gitops-validate: none of them -- treating as a failure, not a pass." >&2
    exit 1
  fi
  if [ -z "${DISABLED_SKIPPED}" ] || [ "${DISABLED_SKIPPED}" -ne 0 ]; then
    echo "gitops-validate: ${DISABLED_SKIPPED:-?} .disabled manifest(s) were SKIPPED rather than" >&2
    echo "gitops-validate: validated. A skip exits 0 under -ignore-missing-schemas, so this" >&2
    echo "gitops-validate: would otherwise be a green check that checked less than it appears." >&2
    echo "gitops-validate: Either a CRD is missing from the catalog, or a file stopped parsing." >&2
    exit 1
  fi
fi

echo "gitops-validate: OK"
