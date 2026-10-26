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

set -euo pipefail

# --- runfiles bootstrap ---
# shellcheck disable=SC1090,SC1091
source "${RUNFILES_DIR:-/dev/null}/bazel_tools/tools/bash/runfiles/runfiles.bash" 2>/dev/null ||
	source "$(grep -sm1 "^bazel_tools/tools/bash/runfiles/runfiles.bash " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null ||
	{
		echo >&2 "ERROR: cannot locate the bash runfiles library"
		exit 1
	}
# --- end runfiles bootstrap ---

PA_SH="$(rlocation "${POWER_AGENT_SH}")"
PA_RS="$(rlocation "${POWER_AGENT_RS}")"
INST_SH="$(rlocation "${INSTALL_SH}")"
INST_RS="$(rlocation "${INSTALL_RS}")"
PLIST_FILE="$(rlocation "${PLIST_RLOC}")"
SRC_DIR_FIXTURE="$(dirname "${PLIST_FILE}")"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

FAKE_BIN="${TMP_DIR}/bin"
mkdir -p "${FAKE_BIN}"

# Fixed `date` and `hostname` so timestamps and default instance names are deterministic.
cat >"${FAKE_BIN}/date" <<'EOF'
#!/usr/bin/env bash
echo "1730000000"
EOF
chmod +x "${FAKE_BIN}/date"

cat >"${FAKE_BIN}/hostname" <<'EOF'
#!/usr/bin/env bash
echo "MacBook-Pro-Test"
EOF
chmod +x "${FAKE_BIN}/hostname"

export PATH="${FAKE_BIN}:${PATH}"

run_power_agent_parity() {
	local case_name="$1"
	shift

	local sh_out="${TMP_DIR}/${case_name}.sh.out"
	local sh_err="${TMP_DIR}/${case_name}.sh.err"
	local rs_out="${TMP_DIR}/${case_name}.rs.out"
	local rs_err="${TMP_DIR}/${case_name}.rs.err"
	local sh_curl_body="${TMP_DIR}/${case_name}.sh.curl"
	local rs_curl_body="${TMP_DIR}/${case_name}.rs.curl"

	local sh_rc=0
	env "$@" CURL_CAPTURE="${sh_curl_body}" "${PA_SH}" >"${sh_out}" 2>"${sh_err}" || sh_rc=$?

	local rs_rc=0
	env "$@" CURL_CAPTURE="${rs_curl_body}" "${PA_RS}" >"${rs_out}" 2>"${rs_err}" || rs_rc=$?

	if [[ "${rs_rc}" -ne "${sh_rc}" ]]; then
		echo >&2 "FAIL [${case_name}]: exit code rs=${rs_rc} != sh=${sh_rc}"
		exit 1
	fi
	if ! cmp -s "${sh_out}" "${rs_out}"; then
		echo >&2 "FAIL [${case_name}]: stdout mismatch"
		diff -u "${sh_out}" "${rs_out}" >&2 || true
		exit 1
	fi
	if ! cmp -s "${sh_err}" "${rs_err}"; then
		echo >&2 "FAIL [${case_name}]: stderr mismatch"
		diff -u "${sh_err}" "${rs_err}" >&2 || true
		exit 1
	fi
	if [[ -f "${sh_curl_body}" || -f "${rs_curl_body}" ]]; then
		if ! cmp -s "${sh_curl_body}" "${rs_curl_body}"; then
			echo >&2 "FAIL [${case_name}]: curl payload mismatch"
			diff -u "${sh_curl_body}" "${rs_curl_body}" >&2 || true
			exit 1
		fi
	fi
}

# --- Fixtures for powermetrics, pmset, ioreg, curl ---------------------------

# 1. Apple Silicon powermetrics
cat >"${TMP_DIR}/pm_as.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
*** Sampled system activity (Mon Oct 26 01:00:00 2026) (700.12ms elapsed) ***
CPU Power: 2450 mW
GPU Power: 680 mW
ANE Power: 120 mW
Combined Power (CPU + GPU + ANE): 3250 mW
OUT
EOF
chmod +x "${TMP_DIR}/pm_as.sh"

# 2. Intel powermetrics
cat >"${TMP_DIR}/pm_intel.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
*** Sampled system activity ***
Intel energy model derived package power (CPUs+GT+SA): 18.75W
OUT
EOF
chmod +x "${TMP_DIR}/pm_intel.sh"

# 3. Empty powermetrics
cat >"${TMP_DIR}/pm_empty.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "${TMP_DIR}/pm_empty.sh"

# 4. pmset AC charging
cat >"${TMP_DIR}/pmset_ac_charging.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
Now drawing from 'AC Power'
 -InternalBattery-0 (id=1234567)	88%; charging; 0:35 remaining present: true
OUT
EOF
chmod +x "${TMP_DIR}/pmset_ac_charging.sh"

# 5. pmset Battery discharging
cat >"${TMP_DIR}/pmset_batt_discharging.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
Now drawing from 'Battery Power'
 -InternalBattery-0 (id=1234567)	54%; discharging; 3:40 remaining present: true
OUT
EOF
chmod +x "${TMP_DIR}/pmset_batt_discharging.sh"

# 6. pmset AC attached (charged, not charging)
cat >"${TMP_DIR}/pmset_ac_attached.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
Now drawing from 'AC Power'
 -InternalBattery-0 (id=1234567)	100%; charged; 0:00 remaining present: true; AC attached
OUT
EOF
chmod +x "${TMP_DIR}/pmset_ac_attached.sh"

# 7. pmset empty
cat >"${TMP_DIR}/pmset_empty.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "${TMP_DIR}/pmset_empty.sh"

# 8. ioreg discharging (unsigned 64-bit overflow wraparound: 2^64 - 1225 = 18446744073709550391)
cat >"${TMP_DIR}/ioreg_discharging.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
+-o AppleSmartBattery  <class AppleSmartBattery, id 0x100000240, registered, matched, active, busy 0 (0 ms), retain 9>
    {
      "InstantAmperage" = 18446744073709550391
      "Voltage" = 11450
    }
OUT
EOF
chmod +x "${TMP_DIR}/ioreg_discharging.sh"

# 9. ioreg charging (positive InstantAmperage -> 0.00 W discharge)
cat >"${TMP_DIR}/ioreg_charging.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
+-o AppleSmartBattery  <class AppleSmartBattery>
    {
      "InstantAmperage" = 1850
      "Voltage" = 12550
    }
OUT
EOF
chmod +x "${TMP_DIR}/ioreg_charging.sh"

# 10. curl success (captures stdin and arguments)
cat >"${TMP_DIR}/curl_ok.sh" <<'EOF'
#!/usr/bin/env bash
if [[ -n "${CURL_CAPTURE:-}" ]]; then
	printf 'ARGS:%s\n' "$*" >"${CURL_CAPTURE}"
	cat >>"${CURL_CAPTURE}"
else
	cat >/dev/null
fi
exit 0
EOF
chmod +x "${TMP_DIR}/curl_ok.sh"

# 11. curl failure
cat >"${TMP_DIR}/curl_fail.sh" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
exit 22
EOF
chmod +x "${TMP_DIR}/curl_fail.sh"

# Case 1: Apple Silicon + AC + charging + DRY_RUN=1
run_power_agent_parity "as_ac_charging_dryrun" \
	CONF_FILE="${TMP_DIR}/nonexistent.conf" \
	POWERMETRICS_BIN="${TMP_DIR}/pm_as.sh" \
	PMSET_BIN="${TMP_DIR}/pmset_ac_charging.sh" \
	IOREG_BIN="${TMP_DIR}/ioreg_charging.sh" \
	CURL_BIN="${TMP_DIR}/curl_ok.sh" \
	DRY_RUN=1

# Case 2: Apple Silicon + Battery + discharging (64-bit unsigned overflow wraparound) + live curl push
run_power_agent_parity "as_batt_discharging_push" \
	CONF_FILE="${TMP_DIR}/nonexistent.conf" \
	POWERMETRICS_BIN="${TMP_DIR}/pm_as.sh" \
	PMSET_BIN="${TMP_DIR}/pmset_batt_discharging.sh" \
	IOREG_BIN="${TMP_DIR}/ioreg_discharging.sh" \
	CURL_BIN="${TMP_DIR}/curl_ok.sh" \
	DRY_RUN=0

# Case 3: Intel package power + AC attached + CONF_FILE override + trailing slash URL
cat >"${TMP_DIR}/custom.conf" <<'EOF'
# Custom conf file override
INSTANCE="intel-nuc-mac"
PUSHGATEWAY_URL="https://push.example.test/"
JOB="custom_power"
EOF
run_power_agent_parity "intel_conf_override_dryrun" \
	CONF_FILE="${TMP_DIR}/custom.conf" \
	POWERMETRICS_BIN="${TMP_DIR}/pm_intel.sh" \
	PMSET_BIN="${TMP_DIR}/pmset_ac_attached.sh" \
	IOREG_BIN="${TMP_DIR}/ioreg_charging.sh" \
	CURL_BIN="${TMP_DIR}/curl_ok.sh" \
	DRY_RUN=1

# Case 4: Empty-parse guard (both powermetrics and pmset return empty)
run_power_agent_parity "empty_parse_guard" \
	CONF_FILE="${TMP_DIR}/nonexistent.conf" \
	POWERMETRICS_BIN="${TMP_DIR}/pm_empty.sh" \
	PMSET_BIN="${TMP_DIR}/pmset_empty.sh" \
	IOREG_BIN="${TMP_DIR}/pm_empty.sh" \
	CURL_BIN="${TMP_DIR}/curl_ok.sh"

# Case 5: Curl push failure
run_power_agent_parity "curl_failure" \
	CONF_FILE="${TMP_DIR}/nonexistent.conf" \
	POWERMETRICS_BIN="${TMP_DIR}/pm_as.sh" \
	PMSET_BIN="${TMP_DIR}/pmset_ac_charging.sh" \
	IOREG_BIN="${TMP_DIR}/ioreg_charging.sh" \
	CURL_BIN="${TMP_DIR}/curl_fail.sh" \
	INSTANCE="test-mac" \
	PUSHGATEWAY_URL="https://pushgateway.lab.ipv1337.dev"

# Case 6: PATH lookup when *_BIN env vars are unset
cp "${TMP_DIR}/pm_as.sh" "${FAKE_BIN}/powermetrics"
cp "${TMP_DIR}/pmset_batt_discharging.sh" "${FAKE_BIN}/pmset"
cp "${TMP_DIR}/ioreg_discharging.sh" "${FAKE_BIN}/ioreg"
cp "${TMP_DIR}/curl_ok.sh" "${FAKE_BIN}/curl"
run_power_agent_parity "path_lookup_dryrun" \
	CONF_FILE="${TMP_DIR}/nonexistent.conf" \
	DRY_RUN=1

# --- Install script vs Rust install parity -----------------------------------

cat >"${TMP_DIR}/id_nonroot.sh" <<'EOF'
#!/usr/bin/env bash
echo "501"
EOF
chmod +x "${TMP_DIR}/id_nonroot.sh"

cat >"${TMP_DIR}/id_root.sh" <<'EOF'
#!/usr/bin/env bash
echo "0"
EOF
chmod +x "${TMP_DIR}/id_root.sh"

cat >"${TMP_DIR}/noop.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${TMP_DIR}/noop.sh"

# Case 7: Non-root refusal
sh_inst_rc=0
ID_BIN="${TMP_DIR}/id_nonroot.sh" "${INST_SH}" >"${TMP_DIR}/inst_nonroot.sh.out" 2>"${TMP_DIR}/inst_nonroot.sh.err" || sh_inst_rc=$?
rs_inst_rc=0
ID_BIN="${TMP_DIR}/id_nonroot.sh" "${INST_RS}" >"${TMP_DIR}/inst_nonroot.rs.out" 2>"${TMP_DIR}/inst_nonroot.rs.err" || rs_inst_rc=$?

if [[ "${sh_inst_rc}" -ne 1 || "${rs_inst_rc}" -ne 1 ]]; then
	echo >&2 "FAIL [install_nonroot]: expected exit 1, got sh=${sh_inst_rc} rs=${rs_inst_rc}"
	exit 1
fi
cmp -s "${TMP_DIR}/inst_nonroot.sh.out" "${TMP_DIR}/inst_nonroot.rs.out"
cmp -s "${TMP_DIR}/inst_nonroot.sh.err" "${TMP_DIR}/inst_nonroot.rs.err"

# Case 8: Root install into DEST_ROOT
DEST_SH="${TMP_DIR}/dest_sh"
DEST_RS="${TMP_DIR}/dest_rs"
mkdir -p "${DEST_SH}/Library/LaunchDaemons" "${DEST_RS}/Library/LaunchDaemons"

ID_BIN="${TMP_DIR}/id_root.sh" \
	CHOWN_BIN="${TMP_DIR}/noop.sh" \
	LAUNCHCTL_BIN="${TMP_DIR}/noop.sh" \
	SRC_DIR="${SRC_DIR_FIXTURE}" \
	AGENT_SRC="${PA_SH}" \
	DEST_ROOT="${DEST_SH}" \
	"${INST_SH}" "my-mac-node" >"${TMP_DIR}/inst_root.sh.out" 2>"${TMP_DIR}/inst_root.sh.err"

ID_BIN="${TMP_DIR}/id_root.sh" \
	CHOWN_BIN="${TMP_DIR}/noop.sh" \
	LAUNCHCTL_BIN="${TMP_DIR}/noop.sh" \
	SRC_DIR="${SRC_DIR_FIXTURE}" \
	AGENT_SRC="${PA_SH}" \
	DEST_ROOT="${DEST_RS}" \
	"${INST_RS}" "my-mac-node" >"${TMP_DIR}/inst_root.rs.out" 2>"${TMP_DIR}/inst_root.rs.err"

cmp -s "${TMP_DIR}/inst_root.sh.out" "${TMP_DIR}/inst_root.rs.out"
cmp -s "${TMP_DIR}/inst_root.sh.err" "${TMP_DIR}/inst_root.rs.err"
cmp -s "${DEST_SH}/usr/local/etc/vitruvian-power-agent.conf" "${DEST_RS}/usr/local/etc/vitruvian-power-agent.conf"
cmp -s "${DEST_SH}/Library/LaunchDaemons/com.vitruvian.power-agent.plist" "${DEST_RS}/Library/LaunchDaemons/com.vitruvian.power-agent.plist"

echo "ok: all macos-power-agent parity cases passed"
