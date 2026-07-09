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

if ! command -v kubeconform >/dev/null 2>&1; then
  echo "gitops-validate: kubeconform not found on PATH" >&2
  exit 1
fi

REPO="${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "${REPO}"

# CRD schemas the k8s-core default set doesn't cover (ArgoCD, Gateway API,
# cert-manager, external-dns DNSEndpoint, sealed-secrets, Envoy Gateway, …).
CATALOG='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

echo "gitops-validate: kubeconform over gitops/argocd ..."

# Only *.yaml manifests — NOT the Grafana dashboard .json files under
# platform/grafana-dashboards (those are configMapGenerator inputs, not k8s
# resources; kubeconform would reject them for a missing 'kind').
#
# -strict                    reject duplicate keys + unknown fields.
# -ignore-missing-schemas    CRDs not in the catalog (e.g. Cilium, k3s
#                            HelmChartConfig) are SKIPPED, not failed — so this
#                            validates everything schema-known without
#                            false-failing on the exotic CRDs.
mkdir -p /tmp/kubeconform-cache

find gitops/argocd -name '*.yaml' -print0 \
  | xargs -0 kubeconform \
      -n 1 \
      -cache /tmp/kubeconform-cache \
      -strict \
      -ignore-missing-schemas \
      -schema-location default \
      -schema-location "${CATALOG}" \
      -summary

echo "gitops-validate: OK"
