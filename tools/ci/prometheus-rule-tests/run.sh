#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# Runs promtool's rule unit tests against the alerting rules as they are ACTUALLY
# defined in gitops/argocd/platform/prometheus/applicationset.yaml.
#
# The rules are EXTRACTED here at run time, never committed as a copy. A checked-in
# duplicate of the rules would pass forever while the deployed rules drifted away
# from it -- testing a stale artifact is worse than not testing, because it reports
# success. Everything under test therefore comes out of the one file that is
# actually deployed.
#
# Run locally with `bash tools/ci/prometheus-rule-tests/run.sh`; needs promtool and
# PyYAML.
set -eu

APPSET="gitops/argocd/platform/prometheus/applicationset.yaml"
HERE="$(cd "$(dirname "$0")" && pwd)"

fail() { echo "prometheus-rule-tests: $*" >&2; exit 1; }

command -v promtool >/dev/null 2>&1 \
  || fail "promtool not found on PATH (install prometheus, or use the CI job)"
python3 -c "import yaml" 2>/dev/null || fail "PyYAML not importable -- pip install pyyaml"
[ -f "${APPSET}" ] || fail "${APPSET} not found (run from the repo root)"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# The helm values block is a Go raw-string literal wrapped in goTemplate
# delimiters; strip those to get back real YAML.
python3 - "${APPSET}" "${WORK}/rules.yml" <<'PY'
import re, sys, yaml

appset, out = sys.argv[1], sys.argv[2]
doc = yaml.safe_load(open(appset))
values = doc["spec"]["template"]["spec"]["source"]["helm"]["values"].strip()
values = re.sub(r"^\{\{`\s*\n", "", values)
values = re.sub(r"\n\s*`\}\}$", "", values)
parsed = yaml.safe_load(values)

rules = parsed.get("serverFiles", {}).get("alerting_rules.yml")
if not rules or not rules.get("groups"):
    raise SystemExit("no alerting_rules.yml groups found -- extraction is broken, "
                     "not the rules; fix this script rather than deleting the test")
yaml.safe_dump(rules, open(out, "w"), default_flow_style=False)
print(f"prometheus-rule-tests: extracted {len(rules['groups'])} rule group(s)")
PY

promtool check rules "${WORK}/rules.yml" >/dev/null \
  || fail "extracted rules are not valid"

# Each *.test.yml names `rules.yml` relative to itself, so run from WORK with the
# test files copied alongside the freshly extracted rules.
cp "${HERE}"/*.test.yml "${WORK}/"

rc=0
for t in "${WORK}"/*.test.yml; do
  echo "prometheus-rule-tests: $(basename "$t")"
  ( cd "${WORK}" && promtool test rules "$(basename "$t")" ) || rc=1
done

[ "${rc}" -eq 0 ] || fail "rule unit tests failed"
echo "prometheus-rule-tests: all rule unit tests pass"
