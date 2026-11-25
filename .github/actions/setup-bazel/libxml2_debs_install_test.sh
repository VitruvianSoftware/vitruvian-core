#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Tests the install_all path of libxml2_debs.sh with stubbed dpkg, curl,
# ldconfig, and sudo on PATH.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIBXML2_DEBS_SCRIPT="${LIBXML2_DEBS_SCRIPT:-${SCRIPT_DIR}/libxml2_debs.sh}"

# shellcheck source=libxml2_debs.sh
source "$LIBXML2_DEBS_SCRIPT"

sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	else
		shasum -a 256 "$1" | awk '{print $1}'
	fi
}

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

FIXTURES_DIR="${WORK_DIR}/fixtures"
STUB_BIN="${WORK_DIR}/bin"
STATE_DIR="${WORK_DIR}/state"
CACHE_DIR="${WORK_DIR}/cache"
mkdir -p "$FIXTURES_DIR" "$STUB_BIN" "$STATE_DIR" "$CACHE_DIR"

printf 'fixture-good-libicu74-deb-payload\n' >"${FIXTURES_DIR}/good_icu.deb"
printf 'fixture-good-libxml2-deb-payload\n' >"${FIXTURES_DIR}/good_xml.deb"
printf 'fixture-bad-libicu74-deb-payload\n' >"${FIXTURES_DIR}/bad_icu.deb"
printf 'fixture-bad-libxml2-deb-payload\n' >"${FIXTURES_DIR}/bad_xml.deb"

GOOD_ICU_SHA="$(sha256_of "${FIXTURES_DIR}/good_icu.deb")"
GOOD_XML_SHA="$(sha256_of "${FIXTURES_DIR}/good_xml.deb")"
BAD_ICU_SHA="$(sha256_of "${FIXTURES_DIR}/bad_icu.deb")"
BAD_XML_SHA="$(sha256_of "${FIXTURES_DIR}/bad_xml.deb")"

# Override production SHA256s and URLs only in this test process.
LIBICU74_SHA256="$GOOD_ICU_SHA"
LIBXML2_SHA256="$GOOD_XML_SHA"
LIBICU74_URLS=("http://stub.invalid/libicu74.deb")
LIBXML2_URLS=("http://stub.invalid/libxml2.deb")

cat >"${STUB_BIN}/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF

cat >"${STUB_BIN}/ldconfig" <<'EOF'
#!/usr/bin/env bash
if [ -f "${TEST_STATE_DIR}/installed" ]; then
	echo "	libxml2.so.2 (libc6,x86-64) => /lib/x86_64-linux-gnu/libxml2.so.2"
else
	echo "	libc.so.6 (libc6,x86-64) => /lib/x86_64-linux-gnu/libc.so.6"
fi
EOF

cat >"${STUB_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out=""
url=""
while [ "$#" -gt 0 ]; do
	case "$1" in
	-o)
		out="$2"
		shift 2
		;;
	http://*|https://*)
		url="$1"
		shift
		;;
	*)
		shift
		;;
	esac
done
echo "$url" >>"${TEST_STATE_DIR}/curl.log"
mode="${CURL_MODE:-good}"
if [ "$mode" = "fail" ]; then
	exit 1
fi
if [ "$mode" = "corrupt" ]; then
	printf 'corrupt-mirror\n' >"$out"
	exit 0
fi
case "$url" in
*libicu74*) cp "${TEST_FIXTURES_DIR}/good_icu.deb" "$out" ;;
*libxml2*) cp "${TEST_FIXTURES_DIR}/good_xml.deb" "$out" ;;
*) exit 1 ;;
esac
EOF

cat >"${STUB_BIN}/dpkg" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >>"${TEST_STATE_DIR}/dpkg.log"
sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	else
		shasum -a 256 "$1" | awk '{print $1}'
	fi
}
if [ "${1:-}" = "-i" ]; then
	shift
	for deb in "$@"; do
		printf '%s:%s\n' "$(basename "$deb")" "$(sha256_of "$deb")" >>"${TEST_STATE_DIR}/dpkg_shas.log"
	done
fi
touch "${TEST_STATE_DIR}/installed"
EOF

chmod +x "${STUB_BIN}/sudo" "${STUB_BIN}/ldconfig" "${STUB_BIN}/curl" "${STUB_BIN}/dpkg"

export PATH="${STUB_BIN}:${PATH}"
export TEST_STATE_DIR="$STATE_DIR"
export TEST_FIXTURES_DIR="$FIXTURES_DIR"

reset_state() {
	rm -rf "${STATE_DIR:?}"/* "${CACHE_DIR:?}"/*
	unset CURL_MODE || true
}

fail() {
	echo "FAIL: $1" >&2
	exit 1
}

# Case 1: Valid cached debs -> installed without any curl call.
reset_state
cp "${FIXTURES_DIR}/good_icu.deb" "${CACHE_DIR}/libicu74.deb"
cp "${FIXTURES_DIR}/good_xml.deb" "${CACHE_DIR}/libxml2.deb"
install_all "$CACHE_DIR"
[ ! -e "${STATE_DIR}/curl.log" ] || fail "case 1: unexpected curl call on valid cache"
grep -q -- '-i' "${STATE_DIR}/dpkg.log" || fail "case 1: dpkg -i was not called"
grep -Fxq "libicu74.deb:${GOOD_ICU_SHA}" "${STATE_DIR}/dpkg_shas.log" || fail "case 1: missing good libicu74 sha in dpkg"
grep -Fxq "libxml2.deb:${GOOD_XML_SHA}" "${STATE_DIR}/dpkg_shas.log" || fail "case 1: missing good libxml2 sha in dpkg"

# Case 2: Corrupted cached libxml2.deb -> falls back to mirror for libxml2 only, never passes bad deb to dpkg.
reset_state
cp "${FIXTURES_DIR}/good_icu.deb" "${CACHE_DIR}/libicu74.deb"
cp "${FIXTURES_DIR}/bad_xml.deb" "${CACHE_DIR}/libxml2.deb"
install_all "$CACHE_DIR"
[ -f "${STATE_DIR}/curl.log" ] || fail "case 2: curl was not called on corrupted libxml2 cache"
grep -q 'libxml2.deb' "${STATE_DIR}/curl.log" || fail "case 2: expected curl for libxml2.deb"
if grep -q 'libicu74.deb' "${STATE_DIR}/curl.log"; then
	fail "case 2: unexpected curl for valid cached libicu74.deb"
fi
if grep -q "${BAD_XML_SHA}" "${STATE_DIR}/dpkg_shas.log"; then
	fail "case 2: corrupted cached libxml2.deb was passed to dpkg -i"
fi
grep -Fxq "libicu74.deb:${GOOD_ICU_SHA}" "${STATE_DIR}/dpkg_shas.log" || fail "case 2: missing good libicu74 sha in dpkg"
grep -Fxq "libxml2.deb:${GOOD_XML_SHA}" "${STATE_DIR}/dpkg_shas.log" || fail "case 2: missing good libxml2 sha in dpkg"

# Case 3: Corrupted cached libicu74.deb -> falls back to mirror for libicu74 only, never passes bad deb to dpkg.
reset_state
cp "${FIXTURES_DIR}/bad_icu.deb" "${CACHE_DIR}/libicu74.deb"
cp "${FIXTURES_DIR}/good_xml.deb" "${CACHE_DIR}/libxml2.deb"
install_all "$CACHE_DIR"
[ -f "${STATE_DIR}/curl.log" ] || fail "case 3: curl was not called on corrupted libicu74 cache"
grep -q 'libicu74.deb' "${STATE_DIR}/curl.log" || fail "case 3: expected curl for libicu74.deb"
if grep -q 'libxml2.deb' "${STATE_DIR}/curl.log"; then
	fail "case 3: unexpected curl for valid cached libxml2.deb"
fi
if grep -q "${BAD_ICU_SHA}" "${STATE_DIR}/dpkg_shas.log"; then
	fail "case 3: corrupted cached libicu74.deb was passed to dpkg -i"
fi
grep -Fxq "libicu74.deb:${GOOD_ICU_SHA}" "${STATE_DIR}/dpkg_shas.log" || fail "case 3: missing good libicu74 sha in dpkg"
grep -Fxq "libxml2.deb:${GOOD_XML_SHA}" "${STATE_DIR}/dpkg_shas.log" || fail "case 3: missing good libxml2 sha in dpkg"

# Case 4: Already installed no-op -> neither curl nor dpkg runs.
reset_state
touch "${STATE_DIR}/installed"
install_all "$CACHE_DIR"
[ ! -e "${STATE_DIR}/curl.log" ] || fail "case 4: unexpected curl when libxml2.so.2 already present"
[ ! -e "${STATE_DIR}/dpkg.log" ] || fail "case 4: unexpected dpkg when libxml2.so.2 already present"

# Case 5: Corrupted cached libxml2.deb + mirror failure -> fails non-zero and never runs dpkg -i.
reset_state
cp "${FIXTURES_DIR}/good_icu.deb" "${CACHE_DIR}/libicu74.deb"
cp "${FIXTURES_DIR}/bad_xml.deb" "${CACHE_DIR}/libxml2.deb"
export CURL_MODE=fail
set +e
(
	set -euo pipefail
	install_all "$CACHE_DIR"
)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "case 5: expected install_all to fail when cache is corrupt and mirror fails"
[ ! -e "${STATE_DIR}/dpkg.log" ] || fail "case 5: dpkg -i must not run when fallback download fails"

echo "PASS: all libxml2_debs.sh install tests passed"
