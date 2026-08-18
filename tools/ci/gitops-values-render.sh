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
#
# `helm template` over every REMOTE chart that an ArgoCD Application pairs with a
# values file kept in this repo -- with the chart's own values.schema.json
# ENFORCED. Run locally with `bash tools/ci/gitops-values-render.sh`; needs helm.
#
# WHY THIS EXISTS. #1738 added `serviceAccount` under `backstage:` in
# gitops/argocd/platform/backstage/values.yaml. The upstream chart declares
# serviceAccount as a TOP-LEVEL value and sets `additionalProperties: false` on
# `backstage`, so the values failed schema validation and ArgoCD could not render
# the Application at all:
#
#   ComparisonError: ... at '/backstage': additional properties 'serviceAccount'
#   not allowed
#
# The blast radius is what makes this worth a gate. The failure is not scoped to
# the offending key -- the whole app stops rendering, so it silently freezes at
# its last good state and EVERY subsequent change stops deploying behind it. It
# stayed hidden for hours because `Application.status.health` remains `Healthy`
# throughout: the old ReplicaSet keeps serving, and only `sync.status: Unknown`
# distinguishes it from a working app. Two merged PRs (#1739, #1740) were stranded
# before anyone noticed, and #1738's own Kubernetes plugin never worked either --
# the Deployment kept `serviceAccountName: default`.
#
# WHY THE EXISTING GATES MISSED IT, and why this is a third script rather than a
# change to either:
#   - tools/ci/chart-render.sh renders only CO-LOCATED charts (**/deploy/chart)
#     and with SYNTHETIC values, by design. It says so in its own header: it
#     verifies templates, never a deployment.
#   - tools/ci/gitops-validate.sh deliberately does NOT render remote charts,
#     because rendering all 26 of them is what OOM-killed the argocd repo-server
#     (#422). That reason is sound and still holds.
# Neither covers "our values, their chart" -- which is the only place a schema
# mismatch can exist. This script renders ONLY the pairs that actually exist,
# which is 2 apps today, not 26, so #422's cost argument does not apply.
#
# WHAT IT DOES NOT DO: it renders with the values as committed, so `${VAR}`
# placeholders stay literal (helm never expands them; ArgoCD's chart does that at
# apply time via envsubst in the container). It validates STRUCTURE against the
# chart schema. A green run is not evidence that the resulting workload is
# correct, only that ArgoCD can render it.
set -eu

fail() {
  echo "gitops-values-render: $*" >&2
  exit 1
}

command -v helm >/dev/null 2>&1 || fail "helm not found on PATH"
command -v python3 >/dev/null 2>&1 || fail "python3 not found on PATH"
python3 -c "import yaml" 2>/dev/null \
  || fail "PyYAML not importable -- \`pip install pyyaml\`. The discovery step below \
parses the gitops tree; without it this gate would find no pairs and pass vacuously."

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# Chart+values pairs are DERIVED from the gitops tree, never listed here. A
# hand-maintained list is exactly what rots: adding a third app that pairs a
# remote chart with a repo values file must extend the gate automatically, or the
# gate quietly stops covering the thing it was written for. Completeness is
# enforced below by requiring at least one pair.
PAIRS="${WORK}/pairs.tsv"
python3 - "${PAIRS}" <<'PY'
import glob, sys, yaml

out = []


def specs_of(doc):
    kind = doc.get("kind")
    if kind == "Application":
        return [doc.get("spec", {})]
    if kind == "ApplicationSet":
        return [doc.get("spec", {}).get("template", {}).get("spec", {})]
    return []


for path in glob.glob("gitops/**/*.yaml", recursive=True):
    try:
        docs = list(yaml.safe_load_all(open(path)))
    except Exception:
        # A template-bearing file that isn't parseable as plain YAML is
        # gitops-validate's problem, not this gate's.
        continue
    for doc in docs:
        if not isinstance(doc, dict):
            continue
        for spec in specs_of(doc):
            if not isinstance(spec, dict):
                continue
            sources = spec.get("sources") or (
                [spec["source"]] if spec.get("source") else []
            )
            chart = repo = rev = None
            value_files = []
            for src in sources:
                if not isinstance(src, dict):
                    continue
                if src.get("chart"):
                    chart = src["chart"]
                    repo = src.get("repoURL")
                    rev = src.get("targetRevision")
                for vf in (src.get("helm") or {}).get("valueFiles") or []:
                    # `$values/<path>` is an ArgoCD ref into another source; the
                    # path after it is repo-relative.
                    value_files.append(vf.split("/", 1)[1] if vf.startswith("$values/") else vf)
            if chart and repo and rev and value_files:
                name = doc.get("metadata", {}).get("name", "?")
                for vf in value_files:
                    out.append("\t".join([name, repo, chart, str(rev), vf]))

with open(sys.argv[1], "w") as fh:
    fh.write("\n".join(sorted(set(out))) + ("\n" if out else ""))
PY

[ -s "${PAIRS}" ] || fail "discovered no chart+values pairs -- the discovery query \
matched nothing, which means this gate is inert. Fix the query, do not delete it."

echo "gitops-values-render: $(wc -l < "${PAIRS}" | tr -d ' ') chart+values pair(s) to render"

# GHCR-hosted OCI charts need a registry login even when the package is public:
# helm 4's anonymous token request to ghcr.io is refused with 403 while the same
# manifest fetches fine with a token. In CI the workflow logs in with the job's
# GITHUB_TOKEN before calling this script; locally, `gh auth token` is used if
# `gh` is authenticated. Without either, the OCI pull fails loudly rather than
# being skipped.
oci_login() {
  _host="$1"
  [ -f "${WORK}/.logged-in-${_host}" ] && return 0
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    printf '%s' "${GITHUB_TOKEN}" \
      | helm registry login "${_host}" -u "${GITHUB_ACTOR:-x-access-token}" --password-stdin >/dev/null 2>&1 \
      && touch "${WORK}/.logged-in-${_host}" && return 0
  elif command -v gh >/dev/null 2>&1 && gh auth token >/dev/null 2>&1; then
    gh auth token 2>/dev/null \
      | helm registry login "${_host}" -u "$(gh api user --jq .login 2>/dev/null || echo x-access-token)" --password-stdin >/dev/null 2>&1 \
      && touch "${WORK}/.logged-in-${_host}" && return 0
  fi
  echo "gitops-values-render: no credential for ${_host}; set GITHUB_TOKEN or run \`gh auth login\`" >&2
  return 1
}

# `helm pull` has no --retry. This gate's ONLY remote dependency is these pulls,
# and a transient registry blip must not redden the merge queue for a reason
# unrelated to the change under test -- same rationale as clone_shallow() in
# gitops-validate.sh (#1349).
pull_chart() {
  _repo="$1"; _chart="$2"; _rev="$3"; _dest="$4"
  _attempt=1
  while [ "${_attempt}" -le 3 ]; do
    rm -rf "${_dest}"; mkdir -p "${_dest}"
    case "${_repo}" in
      http://*|https://*)
        helm pull "${_chart}" --repo "${_repo}" --version "${_rev}" \
          --untar --untardir "${_dest}" >/dev/null 2>&1 && return 0
        ;;
      *)
        # ArgoCD writes OCI chart repos without a scheme (repoURL:
        # ghcr.io/block/buzz/charts, chart: buzz) -> oci://<repo>/<chart>.
        oci_login "${_repo%%/*}" || return 1
        helm pull "oci://${_repo}/${_chart}" --version "${_rev}" \
          --untar --untardir "${_dest}" >/dev/null 2>&1 && return 0
        ;;
    esac
    echo "gitops-values-render: pull of ${_chart}@${_rev} failed (attempt ${_attempt}/3), retrying..." >&2
    _attempt=$((_attempt + 1))
    sleep 5
  done
  return 1
}

rc=0
while IFS="$(printf '\t')" read -r app repo chart rev values; do
  [ -n "${app}" ] || continue
  [ -f "${values}" ] || fail "${app}: values file ${values} does not exist"

  dest="${WORK}/${app}"
  if ! pull_chart "${repo}" "${chart}" "${rev}" "${dest}"; then
    fail "${app}: could not pull ${chart} ${rev} from ${repo} after 3 attempts"
  fi

  # --kube-version pins the API-version set so a runner-local helm default cannot
  # change the verdict between machines.
  chartdir="${dest}/${chart}"
  if [ ! -d "${chartdir}" ]; then
    _found="$(find "${dest}" -maxdepth 2 -name Chart.yaml -print -quit)"
    chartdir="${_found:+$(dirname "${_found}")}"
  fi
  [ -n "${chartdir}" ] && [ -d "${chartdir}" ] || fail "${app}: could not locate the unpacked chart under ${dest}"

  if helm template "${chartdir}" \
       --name-template "${app}" \
       --namespace "${app}" \
       --kube-version 1.35.3 \
       --values "${values}" \
       --include-crds \
       >/dev/null 2>"${WORK}/${app}.err"; then
    echo "  ok   ${app}  (${chart}@${rev})"
  else
    echo "  FAIL ${app}  (${chart}@${rev}) values=${values}" >&2
    sed 's/^/       /' "${WORK}/${app}.err" >&2
    rc=1
  fi
done < "${PAIRS}"

[ "${rc}" -eq 0 ] || fail "at least one Application's values do not render against its chart. \
ArgoCD reports this as ComparisonError and STOPS DEPLOYING that app entirely -- \
including unrelated changes queued behind it."

echo "gitops-values-render: all pairs render"
