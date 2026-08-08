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
# `helm template` over every CO-LOCATED chart (**/deploy/chart), with negative
# controls. Run locally with `bash tools/ci/chart-render.sh`; needs only helm.
#
# WHY THIS EXISTS. Nothing in CI rendered a chart before this. gitops-validate
# deliberately does not, and its reason is sound and does NOT apply here: it
# declines to render the 26 REMOTE chart sources in the gitops tree, because
# rendering them all is what OOM-killed the argocd repo-server (#422). These
# charts are local and offline. Different problem, opposite answer.
#
# The cost of the gap was concrete. Every claim anyone made about the mcp-slack
# chart — which `required` calls actually fire, whether the boolean type-check
# rejects a quoted "false", whether the helpers are reached at all — was a
# careful read by someone who could not run it, and several of those reads
# disagreed with each other before converging.
#
# WHAT IT DOES NOT DO, which matters more than what it does: it renders with
# SYNTHETIC values from tools/ci/chart-render/. It verifies the TEMPLATES, never
# a deployment. The real values in gitops/argocd/applications/ are placeholders
# on purpose and no gate can fill them — they are the decisions the placeholders
# exist to force. A green run here is not evidence that anything is safe to
# deploy.

set -euo pipefail

REPO="${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "${REPO}"

VALUES_DIR="tools/ci/chart-render"
FAILURES=0

fail() {
  echo "chart-render: FAIL: $*" >&2
  FAILURES=$((FAILURES + 1))
}

# Charts whose templates carry a `kindIs "string"` type-rejection, and the value
# it guards. Declared rather than derived: the guard can wrap any value, and a
# derivation that silently matched nothing would leave the control ungated while
# looking present. Completeness IS enforced — a chart containing that guard with
# no entry here fails, and an entry naming a chart that no longer has the guard
# fails too, so this cannot rot in either direction.
#
# Format, one per line: <chart-dir> <dotted-values-path>
STRING_REJECT_CONTROLS="mcp-slack/deploy/chart networkPolicy.enabled"

# Every `required "<message>" .Values.<path>` in a chart's templates, as dotted
# paths, deduplicated.
#
# DERIVED, not listed, and that is the point. A hand-maintained list of required
# values is exactly what drifted: this component spent an afternoon disagreeing
# over whether the count was five or six while the deciding fact sat in the
# templates. Extracting it means adding a `required` automatically adds a
# negative control, and cannot silently leave one ungated.
#
# `|| true` on the grep is load-bearing under `set -e`: grep exits 1 when it
# matches nothing, which is the correct and expected result for a chart with no
# `required` calls at all. Without it the script dies on the first such chart —
# which is exactly what the first CI run of this file did, on
# oauth-user-inspector, immediately after mcp-slack passed every assertion. A
# chart having no required values is not an error; it is most charts.
required_paths() {
  { grep -rho 'required "[^"]*" \.Values\.[A-Za-z0-9_.]*' "$1/templates" 2>/dev/null || true; } \
    | sed 's/.*\.Values\.//' \
    | sort -u
}

if ! command -v helm >/dev/null 2>&1; then
  echo "chart-render: helm not found on PATH" >&2
  exit 1
fi

CHARTS="$(find . -path '*/deploy/chart/Chart.yaml' -not -path './bazel-*/*' | sort)"
if [ -z "${CHARTS}" ]; then
  # A zero-chart sweep means the layout moved, not that the repo has no charts.
  # Reporting OK here would be a green check that checked nothing — the same
  # failure gitops-validate.sh guards against for its own kubeconform run.
  echo "chart-render: found no charts under */deploy/chart — layout changed?" >&2
  exit 1
fi

for chart in ${CHARTS}; do
  dir="$(dirname "${chart}")"
  reldir="${dir#./}"
  name="$(awk -F': ' '/^name:/{print $2; exit}' "${chart}")"
  values="${VALUES_DIR}/${name}.values.yaml"

  echo "::group::chart-render: ${reldir} (${name})"

  # One argument vector, used by lint, the positive control and every negative
  # control — so a negative control can never differ from the positive one by
  # anything except the single value it is testing.
  args=("${name}" "${dir}")
  if [ -f "${values}" ]; then
    args+=(-f "${values}")
  fi

  # NEVER MOVE THE NEGATIVE CONTROLS BELOW ONTO `helm lint`. Every assertion in
  # this script that must FAIL uses `helm template` deliberately, because
  # `required` does not fail under lint: helm's own engine special-cases it —
  #
  #   if e.LintMode { log.Printf("[INFO] Missing required value: %s", warn); return "", nil }
  #
  # — so under `lint` a missing required value is an INFO line and a SUCCESSFUL
  # render. A gate rewritten to lint-only would pass on a chart with every guard
  # deleted, which is the precise failure this job exists to detect, delivered
  # by the tool rather than by the chart. `lint` is kept here only as a cheap
  # sanity pass with better messages for a malformed Chart.yaml. Found by Aegis
  # in helm/helm pkg/engine/engine.go.
  if ! lint_out="$(helm lint "${args[@]:1}" 2>&1)"; then
    fail "${reldir}: helm lint"
    printf '%s\n' "${lint_out}" >&2
  fi

  # --- Positive control -----------------------------------------------------
  # Establishes the templates render AT ALL with a complete value set. Without
  # it every negative control below would "pass" on a chart that is simply
  # broken: each render would fail, and failing is what they assert.
  if ! rendered="$(helm template "${args[@]}" 2>&1)"; then
    fail "${reldir}: positive control did not render:"
    printf '%s\n' "${rendered}" >&2
    echo "::endgroup::"
    continue
  fi
  echo "chart-render: ${reldir}: rendered $(printf '%s\n' "${rendered}" | grep -c '^kind:') resources"

  # --- Negative controls: every `required` must actually fire ---------------
  #
  # THIS IS WHAT MAKES IT A GATE. A chart whose `required` calls had all been
  # deleted renders perfectly with the values file above and passes the positive
  # control — from the outside, the guards' absence looks exactly like their
  # presence. So null each required value in turn and assert the render REFUSES.
  #
  # `--set <path>=null` sets the value to nil, which is what `required` tests,
  # rather than to an empty string, which some guards would accept.
  paths="$(required_paths "${dir}")"
  if [ -n "${paths}" ] && [ ! -f "${values}" ]; then
    fail "${reldir}: has required values but no ${values} — it would go ungated"
  fi

  n_paths=0
  for path in ${paths}; do
    n_paths=$((n_paths + 1))
    if err="$(helm template "${args[@]}" --set "${path}=null" 2>&1)"; then
      fail "${reldir}: nulling ${path} still rendered — its 'required' does not fire"
      continue
    fi
    # The message must NAME the value. An operator meets this error with no
    # other context, and "a required value is missing" sends them hunting
    # through templates to find out which. Not style — it is the entire usable
    # content of a fail-closed refusal.
    if ! printf '%s\n' "${err}" | grep -qF "${path}"; then
      fail "${reldir}: nulling ${path} refused the render (good) but the message never names ${path} — name the value in its 'required' text"
    fi
  done
  if [ "${n_paths}" -gt 0 ]; then
    echo "chart-render: ${reldir}: ${n_paths} required value(s), each refuses when absent"
  fi

  # --- Negative control: a quoted boolean must be REFUSED, not believed -----
  #
  # Helm treats any non-empty string as truthy, so `enabled: "false"` — the most
  # natural way to write OFF in a YAML values block — silently means TRUE. A
  # chart guarding that with `kindIs "string"` asserts a property no read of a
  # values file can confirm.
  guarded=""
  while read -r ctl_dir ctl_path; do
    [ -n "${ctl_dir:-}" ] || continue
    if [ "${ctl_dir}" = "${reldir}" ]; then
      guarded="${ctl_path}"
    fi
  done <<EOF
${STRING_REJECT_CONTROLS}
EOF

  if grep -rq 'kindIs "string"' "${dir}/templates" 2>/dev/null; then
    if [ -z "${guarded}" ]; then
      fail "${reldir}: templates carry a kindIs \"string\" guard with no STRING_REJECT_CONTROLS entry — the guard would be untested"
    elif helm template "${args[@]}" --set-string "${guarded}=false" >/dev/null 2>&1; then
      fail "${reldir}: the STRING \"false\" was ACCEPTED for ${guarded} — Helm reads that as true"
    else
      echo "chart-render: ${reldir}: string \"false\" refused for ${guarded}"
    fi
  elif [ -n "${guarded}" ]; then
    fail "${reldir}: STRING_REJECT_CONTROLS names ${guarded} but the templates have no kindIs \"string\" guard — stale entry, or the guard was removed"
  fi

  echo "::endgroup::"
done

if [ "${FAILURES}" -ne 0 ]; then
  echo "chart-render: ${FAILURES} failure(s)" >&2
  exit 1
fi

echo "chart-render: OK"
