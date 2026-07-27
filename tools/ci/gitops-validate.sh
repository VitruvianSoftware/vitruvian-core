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
SCHEMA_DIR="/tmp/k8s-json-schema"
CRD_CATALOG_DIR="/tmp/crd-catalog"

if [ ! -d "${SCHEMA_DIR}" ]; then
  echo "gitops-validate: cloning kubernetes-json-schema..."
  git clone --depth 1 https://github.com/yannh/kubernetes-json-schema.git "${SCHEMA_DIR}"
fi

if [ ! -d "${CRD_CATALOG_DIR}" ]; then
  echo "gitops-validate: cloning CRDs-catalog..."
  git clone --depth 1 https://github.com/datreeio/CRDs-catalog.git "${CRD_CATALOG_DIR}"
fi

find gitops/argocd -name '*.yaml' -print0 \
  | xargs -0 kubeconform \
      -strict \
      -ignore-missing-schemas \
      -schema-location "${SCHEMA_DIR}/master-standalone-strict/{{.ResourceKind}}{{.KindSuffix}}.json" \
      -schema-location "${CRD_CATALOG_DIR}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" \
      -summary

echo "gitops-validate: OK"
