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
# Installs the APK on an attached device and proves the app actually STARTS.
#
# Why this exists. //mobile/android/remote:lib compiles the app; it does not
# assemble :app and it never runs it. Two defects reached main behind that gap
# with every check green:
#
#   #2197  com.google.guava:listenablefuture resolved to the empty placeholder
#          jar, so AbstractResolvableFuture shipped without the interface it
#          implements and ProfileInstaller's startup initializer killed the
#          process before the first frame -- on every device, every launch.
#   #2198  the glass tab bar blurred its own icons and labels into mush.
#
# The first is a RUNTIME class-resolution failure: it compiles perfectly. No
# amount of building catches it. Only launching does.
#
# Three assertions, in the order they fail usefully:
#   1. the first frame is drawn  -- ActivityTaskManager logs "Displayed <pkg>/"
#      exactly then, which is the only unambiguous "the UI came up" signal
#   2. nothing crashed           -- the crash buffer names no <pkg> process
#   3. it is still alive         -- pidof after a settle window, because a
#      startup crash on a background thread (exactly #2197) can happen AFTER
#      the first frame and would otherwise pass
#
# It deliberately does NOT assert anything about what the UI looks like. That
# is screenshot territory and wants its own change; this test only answers
# "does it start". A screenshot is saved to the undeclared-outputs dir anyway,
# so a failure is something you can look at rather than guess about.
set -euo pipefail

# --- runfiles bootstrap (https://github.com/bazelbuild/bazel/tree/master/tools/bash) ---
# shellcheck disable=SC1090,SC1091
source "${RUNFILES_DIR:-/dev/null}/bazel_tools/tools/bash/runfiles/runfiles.bash" 2>/dev/null ||
	source "$(grep -sm1 "^bazel_tools/tools/bash/runfiles/runfiles.bash " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null ||
	{
		echo >&2 "ERROR: cannot locate the bash runfiles library"
		exit 1
	}
# --- end runfiles bootstrap ---

readonly PKG="${APP_PACKAGE:?APP_PACKAGE must be set by the BUILD rule}"
readonly ACTIVITY="${APP_ACTIVITY:?APP_ACTIVITY must be set by the BUILD rule}"
readonly LAUNCH_TIMEOUT_S="${LAUNCH_TIMEOUT_S:-90}"
readonly SETTLE_S="${SETTLE_S:-5}"

apk="$(rlocation "${APK}")"
if [[ ! -f "${apk}" ]]; then
	echo >&2 "ERROR: cannot read the APK at '${apk}'"
	exit 1
fi

# Bazel gives a test a minimal PATH, so an SDK on the developer's own PATH is
# not visible here. Search the usual homes before giving up, and when giving up
# say exactly which flags make a local run work -- this test is `manual`, so
# whoever runs it typed the label deliberately and deserves a real answer.
find_adb() {
	if [[ -n "${ADB:-}" && -x "${ADB}" ]]; then
		echo "${ADB}"
		return 0
	fi
	if command -v adb >/dev/null 2>&1; then
		command -v adb
		return 0
	fi
	local candidate
	for candidate in \
		"${ANDROID_HOME:-}/platform-tools/adb" \
		"${ANDROID_SDK_ROOT:-}/platform-tools/adb" \
		"${HOME:-}/Library/Android/sdk/platform-tools/adb" \
		"${HOME:-}/Android/Sdk/platform-tools/adb" \
		/opt/homebrew/share/android-commandlinetools/platform-tools/adb \
		/usr/local/bin/adb \
		/opt/homebrew/bin/adb; do
		if [[ -n "${candidate}" && -x "${candidate}" ]]; then
			echo "${candidate}"
			return 0
		fi
	done
	return 1
}

if ! adb="$(find_adb)"; then
	cat >&2 <<-EOF
		ERROR: no adb found.

		This test drives a real device or emulator, so it needs the platform-tools
		adb and a device already attached. Bazel scrubs PATH for tests, so pass the
		environment through explicitly:

		  bazel test //mobile/android/remote:boot_smoke \\
		    --test_env=ANDROID_HOME --test_env=PATH --test_output=all

		In CI the android-emulator composite action puts adb on the default PATH
		and boots a device before this runs.
	EOF
	exit 1
fi
readonly adb

# One device, unambiguously. ANDROID_SERIAL wins when it is set; otherwise there
# must be exactly one, because silently picking the first of several would make
# a green run mean nothing in particular.
pick_device() {
	if [[ -n "${ANDROID_SERIAL:-}" ]]; then
		echo "${ANDROID_SERIAL}"
		return 0
	fi
	local devices
	devices="$("${adb}" devices | awk '$2 == "device" { print $1 }')"
	local count
	count="$(printf '%s' "${devices}" | grep -c . || true)"
	if [[ "${count}" -eq 0 ]]; then
		echo >&2 "ERROR: no attached device. Boot an emulator or plug in a phone."
		return 1
	fi
	if [[ "${count}" -gt 1 ]]; then
		echo >&2 "ERROR: ${count} devices attached; set ANDROID_SERIAL to choose one:"
		echo >&2 "${devices}"
		return 1
	fi
	printf '%s' "${devices}"
}

serial="$(pick_device)"
readonly serial
echo "device: ${serial}"

adbd() { "${adb}" -s "${serial}" "$@"; }

outdir="${TEST_UNDECLARED_OUTPUTS_DIR:-${TMPDIR:-/tmp}}"
mkdir -p "${outdir}"
readonly logcat_file="${outdir}/logcat.txt"
readonly crash_file="${outdir}/crash.txt"

# Capture evidence on ANY exit, pass or fail. A green run's screenshot is how a
# reviewer sees what the lane actually saw.
capture_evidence() {
	adbd logcat -d >"${logcat_file}" 2>/dev/null || true
	adbd logcat -b crash -d >"${crash_file}" 2>/dev/null || true
	adbd shell screencap -p /sdcard/boot_smoke.png >/dev/null 2>&1 &&
		adbd pull /sdcard/boot_smoke.png "${outdir}/screen.png" >/dev/null 2>&1 || true
	adbd shell rm -f /sdcard/boot_smoke.png >/dev/null 2>&1 || true
}
trap capture_evidence EXIT

echo "waiting for the device to finish booting"
adbd wait-for-device
boot_deadline=$((SECONDS + LAUNCH_TIMEOUT_S))
until [[ "$(adbd shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')" == "1" ]]; do
	if ((SECONDS >= boot_deadline)); then
		echo >&2 "ERROR: device never reported sys.boot_completed within ${LAUNCH_TIMEOUT_S}s"
		exit 1
	fi
	sleep 2
done

# A leftover install from an earlier run would mask a packaging regression.
adbd uninstall "${PKG}" >/dev/null 2>&1 || true
echo "installing ${apk}"
adbd install -r "${apk}"

# Clear every buffer: the crash assertion below is only meaningful if a crash
# it finds belongs to THIS launch.
adbd logcat -b all -c >/dev/null 2>&1 || adbd logcat -c >/dev/null 2>&1 || true

echo "launching ${PKG}/${ACTIVITY}"
adbd shell am start -n "${PKG}/${ACTIVITY}"

# --- 1. first frame -------------------------------------------------------
# ActivityTaskManager logs "Displayed <pkg>/<activity>: +NNNms" at exactly the
# moment the first frame is drawn. Read logcat into a FILE and grep the file:
# `logcat -d | grep -q` exits 141 on SIGPIPE once the buffer is large, which
# reads as "not found" and would make this assertion quietly useless.
echo "waiting for the first frame"
displayed=""
frame_deadline=$((SECONDS + LAUNCH_TIMEOUT_S))
while ((SECONDS < frame_deadline)); do
	adbd logcat -d >"${logcat_file}" 2>/dev/null || true
	if displayed="$(grep -m1 -F "Displayed ${PKG}/${ACTIVITY}" "${logcat_file}")"; then
		break
	fi
	displayed=""
	# A process that has already died will never draw; fail now with the crash
	# rather than burning the whole timeout.
	adbd logcat -b crash -d >"${crash_file}" 2>/dev/null || true
	if grep -qF "Process: ${PKG}" "${crash_file}"; then
		echo >&2 "ERROR: ${PKG} crashed before drawing its first frame:"
		sed -n '1,40p' "${crash_file}" >&2
		exit 1
	fi
	sleep 2
done

if [[ -z "${displayed}" ]]; then
	echo >&2 "ERROR: ${PKG}/${ACTIVITY} never drew a frame within ${LAUNCH_TIMEOUT_S}s."
	echo >&2 "Last 60 logcat lines:"
	tail -n 60 "${logcat_file}" >&2 || true
	exit 1
fi
echo "first frame: ${displayed##*ActivityTaskManager: }"

# --- 2 and 3. survives the settle window -----------------------------------
# #2197 crashed on a background thread during startup. Depending on timing that
# can land after the first frame, so a first-frame-only assertion could have
# gone green on the very bug this test exists to catch.
echo "settling for ${SETTLE_S}s"
sleep "${SETTLE_S}"

adbd logcat -b crash -d >"${crash_file}" 2>/dev/null || true
if grep -qF "Process: ${PKG}" "${crash_file}"; then
	echo >&2 "ERROR: ${PKG} crashed during startup:"
	sed -n '1,40p' "${crash_file}" >&2
	exit 1
fi

pid="$(adbd shell pidof "${PKG}" 2>/dev/null | tr -d '\r\n')"
if [[ -z "${pid}" ]]; then
	echo >&2 "ERROR: ${PKG} is no longer running ${SETTLE_S}s after launch,"
	echo >&2 "       and left nothing in the crash buffer. Last 60 logcat lines:"
	tail -n 60 "${logcat_file}" >&2 || true
	exit 1
fi

echo "ok: ${PKG} drew its first frame and is still running (pid ${pid})"
