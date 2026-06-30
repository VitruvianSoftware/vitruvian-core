#!/bin/bash
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

# vitruvian macos-power-agent — sample this Mac's compute power and battery, then
# push to the homelab Prometheus Pushgateway. Designed to run as a LaunchDaemon
# (root), so powermetrics needs no sudo. One-shot: sample, push, exit — launchd
# re-runs it every StartInterval. Feeds the "Node Power" Grafana dashboard.
#
# Metrics pushed (gauges, labels job=<JOB> instance=<INSTANCE>):
#   mac_soc_power_watts            SoC package power (Apple Silicon: CPU+GPU+ANE
#                                  combined; Intel: derived package power)
#   mac_cpu_power_watts            CPU-domain power      (Apple Silicon only)
#   mac_gpu_power_watts            GPU-domain power      (Apple Silicon only)
#   mac_ane_power_watts            Neural-engine power   (Apple Silicon only)
#   mac_battery_percent            charge %
#   mac_ac_online                  1 if on AC, else 0
#   mac_battery_charging           1 if charging, else 0
#   mac_battery_discharge_watts    battery draw (>0 only off AC)
#   mac_power_agent_last_push_seconds  unix ts of this push (staleness probe)
set -uo pipefail

# Defaults; override via /usr/local/etc/vitruvian-power-agent.conf (written by
# install.sh) or the environment. INSTANCE defaults to the lowercased short
# hostname, which matches the tailnet/k8s node names (james-macbook-pro, ...).
PUSHGATEWAY_URL="${PUSHGATEWAY_URL:-https://pushgateway.lab.ipv1337.dev}"
INSTANCE="${INSTANCE:-$(hostname -s | tr '[:upper:]' '[:lower:]')}"
JOB="${JOB:-mac_power}"
CONF="/usr/local/etc/vitruvian-power-agent.conf"
# shellcheck disable=SC1090
[ -r "$CONF" ] && . "$CONF"

# --- SoC power via a single powermetrics sample -----------------------------
pm="$(/usr/bin/powermetrics --samplers cpu_power -n 1 -i 700 2>/dev/null)"

# Apple Silicon: "Combined Power (CPU + GPU + ANE): N mW".
# Intel:         "Intel energy model derived package power (CPUs+GT+SA): N.NNW".
soc_w=""
combined_mw="$(printf '%s\n' "$pm" | awk -F': ' '/Combined Power/ {v = $2; sub(/ *mW.*/, "", v); print v; exit}')"
if [ -n "$combined_mw" ]; then
	soc_w="$(awk -v m="$combined_mw" 'BEGIN { printf "%.3f", m / 1000 }')"
else
	intel_w="$(printf '%s\n' "$pm" | sed -nE 's/.*derived package power[^:]*: *([0-9.]+) *W.*/\1/p' | head -1)"
	[ -n "$intel_w" ] && soc_w="$intel_w"
fi

# Per-domain figures (Apple Silicon only; empty on Intel).
domain_mw() { # $1 = domain label, e.g. CPU / GPU / ANE
	printf '%s\n' "$pm" | awk -F': ' -v k="$1 Power" 'index($0, k ":") == 1 {v = $2; sub(/ *mW.*/, "", v); print v; exit}'
}
cpu_mw="$(domain_mw CPU)"
gpu_mw="$(domain_mw GPU)"
ane_mw="$(domain_mw ANE)"

# --- battery via pmset + ioreg ----------------------------------------------
batt="$(/usr/bin/pmset -g batt 2>/dev/null)"
pct="$(printf '%s\n' "$batt" | grep -oE '[0-9]+%' | head -1 | tr -d '%')"
ac=0
printf '%s\n' "$batt" | grep -qiE "AC Power|AC attached" && ac=1
charging=0
printf '%s\n' "$batt" | grep -qiE "; charging" && charging=1

# InstantAmperage is reported as an unsigned 64-bit int; when discharging it is
# 2^64-N. bash arithmetic is signed 64-bit and wraps on overflow, recovering the
# negative value. Voltage is in mV, amperage in mA: watts = |amp| * volt / 1e6.
ioreg="$(/usr/sbin/ioreg -rn AppleSmartBattery 2>/dev/null)"
amp_raw="$(printf '%s\n' "$ioreg" | awk -F'= ' '/"InstantAmperage"/ {gsub(/[^0-9-]/, "", $2); print $2; exit}')"
volt="$(printf '%s\n' "$ioreg" | awk -F'= ' '/"Voltage"/ {gsub(/[^0-9-]/, "", $2); print $2; exit}')"
discharge_w=""
if [ -n "${amp_raw:-}" ] && [ -n "${volt:-}" ]; then
	amp=$((amp_raw))
	discharge_w="$(awk -v a="$amp" -v v="$volt" 'BEGIN { w = (a < 0) ? (-a) * v / 1000000 : 0; printf "%.2f", w }')"
fi

# --- assemble Prometheus exposition -----------------------------------------
metrics=""
emit() { # $1 = metric name, $2 = value
	metrics="${metrics}# TYPE $1 gauge"$'\n'"$1 $2"$'\n'
}
[ -n "$soc_w" ] && emit mac_soc_power_watts "$soc_w"
[ -n "$cpu_mw" ] && emit mac_cpu_power_watts "$(awk -v m="$cpu_mw" 'BEGIN { printf "%.3f", m / 1000 }')"
[ -n "$gpu_mw" ] && emit mac_gpu_power_watts "$(awk -v m="$gpu_mw" 'BEGIN { printf "%.3f", m / 1000 }')"
[ -n "$ane_mw" ] && emit mac_ane_power_watts "$(awk -v m="$ane_mw" 'BEGIN { printf "%.3f", m / 1000 }')"
[ -n "$pct" ] && emit mac_battery_percent "$pct"
emit mac_ac_online "$ac"
emit mac_battery_charging "$charging"
[ -n "$discharge_w" ] && emit mac_battery_discharge_watts "$discharge_w"
emit mac_power_agent_last_push_seconds "$(date +%s)"

# Guard: if neither power nor battery parsed, something is wrong — skip the push
# rather than overwrite a good group with an almost-empty one.
if [ -z "$soc_w" ] && [ -z "$pct" ]; then
	echo "power-agent: nothing parsed (powermetrics/pmset failed?); not pushing" >&2
	exit 0
fi

# DRY_RUN=1: print what would be pushed and exit (for testing).
if [ "${DRY_RUN:-0}" = "1" ]; then
	printf 'target: %s/metrics/job/%s/instance/%s\n' "${PUSHGATEWAY_URL%/}" "$JOB" "$INSTANCE"
	printf '%s' "$metrics"
	exit 0
fi

if ! printf '%s' "$metrics" | /usr/bin/curl -sS --max-time 15 --data-binary @- \
	"${PUSHGATEWAY_URL%/}/metrics/job/${JOB}/instance/${INSTANCE}" >/dev/null 2>&1; then
	echo "power-agent: push to ${PUSHGATEWAY_URL} failed (instance=${INSTANCE})" >&2
	exit 0
fi

exit 0
