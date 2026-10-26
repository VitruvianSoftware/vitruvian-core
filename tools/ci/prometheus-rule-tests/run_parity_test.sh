#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
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
# Hermetic parity test for tools/ci/prometheus-rule-tests/run.sh vs :run.

set -uo pipefail

SH_RUN="${1:?missing run.sh path}"
RS_RUN="${2:?missing :run binary path}"

case "${SH_RUN}" in /*) ;; *) SH_RUN="${PWD}/${SH_RUN}" ;; esac
case "${RS_RUN}" in /*) ;; *) RS_RUN="${PWD}/${RS_RUN}" ;; esac

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

pass=0
fail=0

setup_sandbox() {
  local dir="$1"
  rm -rf "${dir}"
  mkdir -p "${dir}/bin" \
           "${dir}/repo/gitops/argocd/platform/prometheus" \
           "${dir}/repo/tools/ci/prometheus-rule-tests"

  cp "${SH_RUN}" "${dir}/repo/tools/ci/prometheus-rule-tests/run.sh"
  chmod +x "${dir}/repo/tools/ci/prometheus-rule-tests/run.sh"
  cp "${RS_RUN}" "${dir}/repo/tools/ci/prometheus-rule-tests/run-rs"
  chmod +x "${dir}/repo/tools/ci/prometheus-rule-tests/run-rs"

  cat > "${dir}/repo/tools/ci/prometheus-rule-tests/argocd.test.yml" <<'EOF'
rule_files:
  - rules.yml
tests: []
EOF
  cat > "${dir}/repo/tools/ci/prometheus-rule-tests/oom.test.yml" <<'EOF'
rule_files:
  - rules.yml
tests: []
EOF

  cat > "${dir}/repo/gitops/argocd/platform/prometheus/applicationset.yaml" <<'EOF'
spec:
  template:
    spec:
      source:
        helm:
          values: |
            {{`
            serverFiles:
              alerting_rules.yml:
                groups:
                  - name: argocd
                    rules: []
                  - name: oom
                    rules: []
            `}}
EOF

  # Provide standard utilities in bin via symlinks so we can selectively omit promtool/python3
  for tool in bash basename cp dirname mktemp rm cat cd; do
    if p="$(command -v "${tool}" 2>/dev/null)" && [ -x "${p}" ]; then
      ln -sf "${p}" "${dir}/bin/${tool}"
    fi
  done
}

install_stub_promtool() {
  local dir="$1"
  local check_rc="${2:-0}"
  local fail_suite="${3:-}"
  cat > "${dir}/bin/promtool" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "check" ] && [ "\$2" = "rules" ]; then
  [ -f "\$3" ] || exit 2
  echo "Checking \$3"
  exit ${check_rc}
fi
if [ "\$1" = "test" ] && [ "\$2" = "rules" ]; then
  [ -f "rules.yml" ] || { echo "missing rules.yml" >&2; exit 2; }
  [ -f "\$3" ] || { echo "missing \$3" >&2; exit 2; }
  if [ "\$3" = "${fail_suite}" ]; then
    echo "  FAILED: \$3" >&2
    exit 1
  fi
  echo "  SUCCESS"
  exit 0
fi
exit 1
EOF
  chmod +x "${dir}/bin/promtool"
}

install_stub_python3() {
  local dir="$1"
  local import_rc="${2:-0}"
  local groups_count="${3:-2}"
  cat > "${dir}/bin/python3" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "-c" ]; then
  exit ${import_rc}
fi
if [ "\$1" = "-" ]; then
  appset="\$2"
  out="\$3"
  cat >/dev/null
  if [ "${groups_count}" -eq 0 ]; then
    echo "no alerting_rules.yml groups found -- extraction is broken, not the rules; fix this script rather than deleting the test" >&2
    exit 1
  fi
  printf "groups:\n  - name: test\n    rules: []\n" > "\${out}"
  echo "prometheus-rule-tests: extracted ${groups_count} rule group(s)"
  exit 0
fi
exit 1
EOF
  chmod +x "${dir}/bin/python3"
}

run_case() {
  local label="$1"
  local setup_fn="$2"

  setup_sandbox "${WORK}/sh"
  "${setup_fn}" "${WORK}/sh"
  setup_sandbox "${WORK}/rs"
  "${setup_fn}" "${WORK}/rs"

  (
    cd "${WORK}/sh/repo" &&
    PATH="${WORK}/sh/bin" "${WORK}/sh/repo/tools/ci/prometheus-rule-tests/run.sh"
  ) >"${WORK}/sh.stdout" 2>"${WORK}/sh.stderr"
  local sh_rc=$?

  (
    cd "${WORK}/rs/repo" &&
    PATH="${WORK}/rs/bin" "${WORK}/rs/repo/tools/ci/prometheus-rule-tests/run-rs"
  ) >"${WORK}/rs.stdout" 2>"${WORK}/rs.stderr"
  local rs_rc=$?

  local ok=1
  diff -u "${WORK}/sh.stdout" "${WORK}/rs.stdout" >"${WORK}/diff.stdout" 2>&1 || ok=0
  diff -u "${WORK}/sh.stderr" "${WORK}/rs.stderr" >"${WORK}/diff.stderr" 2>&1 || ok=0
  [ "${sh_rc}" = "${rs_rc}" ] || ok=0

  if [ "${ok}" -eq 1 ]; then
    echo "PASS: ${label}"
    pass=$((pass + 1))
  else
    echo "FAIL: ${label} (sh_rc=${sh_rc}, rs_rc=${rs_rc})" >&2
    [ -s "${WORK}/diff.stdout" ] && cat "${WORK}/diff.stdout" >&2
    [ -s "${WORK}/diff.stderr" ] && cat "${WORK}/diff.stderr" >&2
    fail=$((fail + 1))
  fi
}

case_missing_promtool() {
  local d="$1"
  install_stub_python3 "${d}" 0 2
}

case_missing_pyyaml() {
  local d="$1"
  install_stub_promtool "${d}" 0 ""
  install_stub_python3 "${d}" 1 2
}

case_missing_appset() {
  local d="$1"
  install_stub_promtool "${d}" 0 ""
  install_stub_python3 "${d}" 0 2
  rm -f "${d}/repo/gitops/argocd/platform/prometheus/applicationset.yaml"
}

case_empty_groups() {
  local d="$1"
  install_stub_promtool "${d}" 0 ""
  install_stub_python3 "${d}" 0 0
}

case_invalid_rules() {
  local d="$1"
  install_stub_promtool "${d}" 1 ""
  install_stub_python3 "${d}" 0 2
}

case_unit_test_failure() {
  local d="$1"
  install_stub_promtool "${d}" 0 "oom.test.yml"
  install_stub_python3 "${d}" 0 2
}

case_all_pass() {
  local d="$1"
  install_stub_promtool "${d}" 0 ""
  install_stub_python3 "${d}" 0 2
}

run_case "missing promtool" case_missing_promtool
run_case "missing PyYAML" case_missing_pyyaml
run_case "missing applicationset.yaml" case_missing_appset
run_case "extraction finds 0 groups" case_empty_groups
run_case "promtool check rules fails" case_invalid_rules
run_case "promtool test rules fails on one file" case_unit_test_failure
run_case "all rule unit tests pass" case_all_pass

echo ""
echo "Summary: ${pass} passed, ${fail} failed"
[ "${fail}" -eq 0 ]
