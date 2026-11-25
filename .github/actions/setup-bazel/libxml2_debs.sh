#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Single source of truth for the Ubuntu 24.04 (noble) libicu74 + libxml2
# 2.9.14 .deb packages required by toolchains_llvm's ld.lld on Ubuntu 26.04+.
# Shared by .github/actions/setup-bazel (restore/install with mirror fallback)
# and .github/actions/bazel-repo-cache-warm (save to ci-debs cache).

set -euo pipefail

LIBICU74_NAME="libicu74.deb"
LIBICU74_SHA256="c9a70989678660eed9a1e904c74fa043da8bec8e2036856fc16e31ced79b04f8"
LIBICU74_URLS=(
	"http://archive.ubuntu.com/ubuntu/pool/main/i/icu/libicu74_74.2-1ubuntu3.1_amd64.deb"
	"http://security.ubuntu.com/ubuntu/pool/main/i/icu/libicu74_74.2-1ubuntu3.1_amd64.deb"
	"http://azure.archive.ubuntu.com/ubuntu/pool/main/i/icu/libicu74_74.2-1ubuntu3.1_amd64.deb"
	"https://snapshot.ubuntu.com/ubuntu/20261025T000000Z/pool/main/i/icu/libicu74_74.2-1ubuntu3.1_amd64.deb"
)

LIBXML2_NAME="libxml2.deb"
LIBXML2_SHA256="c5a065f85c1e6f605741e365e40cad71c3ceb0e85e2791400bd35b8896e12ad1"
LIBXML2_URLS=(
	"http://archive.ubuntu.com/ubuntu/pool/main/libx/libxml2/libxml2_2.9.14+dfsg-1.3ubuntu3.10_amd64.deb"
	"http://security.ubuntu.com/ubuntu/pool/main/libx/libxml2/libxml2_2.9.14+dfsg-1.3ubuntu3.10_amd64.deb"
	"http://azure.archive.ubuntu.com/ubuntu/pool/main/libx/libxml2/libxml2_2.9.14+dfsg-1.3ubuntu3.10_amd64.deb"
	"https://snapshot.ubuntu.com/ubuntu/20261025T000000Z/pool/main/libx/libxml2/libxml2_2.9.14+dfsg-1.3ubuntu3.10_amd64.deb"
)

verify_sha256() {
	local expected="$1"
	local file="$2"
	[ -f "$file" ] || return 1
	if command -v sha256sum >/dev/null 2>&1; then
		echo "${expected}  ${file}" | sha256sum -c - >/dev/null 2>&1
	else
		echo "${expected}  ${file}" | shasum -a 256 -c - >/dev/null 2>&1
	fi
}

# Herestring, not `ldconfig -p | grep -q`: under pipefail an early-exit
# grep can SIGPIPE ldconfig on large output and flip the verdict.
has_libxml2_so2() {
	grep -q 'libxml2\.so\.2 ' <<<"$(ldconfig -p)"
}

download_verified() {
	local name="$1"
	local sha="$2"
	local dest="$3"
	shift 3
	local tmp="${dest}.tmp.$$"
	for url in "$@"; do
		if curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 --retry-all-errors -o "$tmp" "$url"; then
			if verify_sha256 "$sha" "$tmp"; then
				mv -f "$tmp" "$dest"
				return 0
			fi
		fi
		rm -f "$tmp"
	done
	echo "::error::failed to fetch ${name} from any mirror" >&2
	return 1
}

fetch_all() {
	local dest_dir="$1"
	mkdir -p "$dest_dir"

	local icu_dest="${dest_dir}/${LIBICU74_NAME}"
	if verify_sha256 "$LIBICU74_SHA256" "$icu_dest"; then
		echo "Using verified ${LIBICU74_NAME} from ${dest_dir}"
	else
		download_verified "$LIBICU74_NAME" "$LIBICU74_SHA256" "$icu_dest" "${LIBICU74_URLS[@]}"
	fi

	local xml_dest="${dest_dir}/${LIBXML2_NAME}"
	if verify_sha256 "$LIBXML2_SHA256" "$xml_dest"; then
		echo "Using verified ${LIBXML2_NAME} from ${dest_dir}"
	else
		download_verified "$LIBXML2_NAME" "$LIBXML2_SHA256" "$xml_dest" "${LIBXML2_URLS[@]}"
	fi
}

install_all() {
	local cache_dir="${1:-}"
	if has_libxml2_so2; then
		echo "libxml2.so.2 already present -- nothing to do"
		return 0
	fi

	local dir
	dir="$(mktemp -d)"
	trap 'rm -rf "$dir"' RETURN

	local icu_cached="${cache_dir}/${LIBICU74_NAME}"
	local xml_cached="${cache_dir}/${LIBXML2_NAME}"

	if [ -n "$cache_dir" ] && verify_sha256 "$LIBICU74_SHA256" "$icu_cached"; then
		echo "Cache hit for ${LIBICU74_NAME} (${LIBICU74_SHA256})"
		cp "$icu_cached" "${dir}/${LIBICU74_NAME}"
	else
		echo "Cache miss/mismatch for ${LIBICU74_NAME}; fetching from Ubuntu mirrors"
		download_verified "$LIBICU74_NAME" "$LIBICU74_SHA256" "${dir}/${LIBICU74_NAME}" "${LIBICU74_URLS[@]}" || return 1
	fi

	if [ -n "$cache_dir" ] && verify_sha256 "$LIBXML2_SHA256" "$xml_cached"; then
		echo "Cache hit for ${LIBXML2_NAME} (${LIBXML2_SHA256})"
		cp "$xml_cached" "${dir}/${LIBXML2_NAME}"
	else
		echo "Cache miss/mismatch for ${LIBXML2_NAME}; fetching from Ubuntu mirrors"
		download_verified "$LIBXML2_NAME" "$LIBXML2_SHA256" "${dir}/${LIBXML2_NAME}" "${LIBXML2_URLS[@]}" || return 1
	fi

	sudo dpkg -i "${dir}/${LIBICU74_NAME}" "${dir}/${LIBXML2_NAME}"
	has_libxml2_so2 || {
		echo "::error::libxml2.so.2 still missing after install" >&2
		return 1
	}
	echo "installed libxml2.so.2 (noble 2.9.14) for LLVM's linker"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	cmd="${1:-}"
	case "$cmd" in
	sha-key)
		printf '%s-%s\n' "$LIBICU74_SHA256" "$LIBXML2_SHA256"
		;;
	has-libxml2)
		has_libxml2_so2
		;;
	fetch)
		[ "$#" -eq 2 ] || {
			echo "usage: $0 fetch <dest_dir>" >&2
			exit 2
		}
		fetch_all "$2"
		;;
	install)
		[ "$#" -le 2 ] || {
			echo "usage: $0 install [cache_dir]" >&2
			exit 2
		}
		install_all "${2:-}"
		;;
	*)
		echo "usage: $0 {sha-key|has-libxml2|fetch <dest_dir>|install [cache_dir]}" >&2
		exit 2
		;;
	esac
fi
