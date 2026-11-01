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

# Launcher for cloud-bootstrap, the Rust tool in src/cloud_bootstrap/ (see
# README.md; `bazel run //tools/cloud-bootstrap[:<subcommand>]` runs the same
# code).
#
# This path is how it runs at session start: .claude/session-start.sh calls it
# with no arguments (`up`), and the cloud environment's Setup script calls
# `install --force`. Both run before Bazel exists (this tool is what installs
# Bazel), so the launcher builds the std-only crate with the image's own rustc,
# keeps the binary under $HOME keyed on the rustc version and the sources, and
# runs it. A later session (or the Setup script's cached image) reuses the
# build; a changed source rebuilds. With no rustc it falls back to `bazel run`
# when bazel is installed, which is the usual case on a laptop.
#
# Same contract as the tool: `up`, `install` and `auth` never block a session,
# so if the tool cannot be built they say why and exit 0; anything else exits 1.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="${here}/src/cloud_bootstrap"
sub="${1:-up}"

# On stderr and stdout: the hook's stdout is what the agent sees.
give_up() {
	printf 'cloud-bootstrap: %s\n' "$1" >&2
	printf 'cloud-bootstrap: %s\n' "$1"
	case "${sub}" in
	up | install | auth) exit 0 ;;
	*) exit 1 ;;
	esac
}

# The checkout this launcher lives in: the tool's workspace when neither
# BUILD_WORKSPACE_DIRECTORY nor CLAUDE_PROJECT_DIR names one.
CLOUD_BOOTSTRAP_WORKSPACE="${CLOUD_BOOTSTRAP_WORKSPACE:-$(cd "${here}/../.." && pwd)}"
export CLOUD_BOOTSTRAP_WORKSPACE

# rustc runs from / and without RUSTUP_TOOLCHAIN: rustup picks the compiler
# from a rust-toolchain(.toml) in the working directory or any parent, so from
# the checkout a file in the repo (or a branch being reviewed) could swap in a
# compiler that then runs with the session's credentials. From /, only the
# user's own rustup default decides. (RUSTC is read by cargo, not by rustc or
# rustup's rustc proxy; this calls rustc directly.)
trusted_rustc() { (cd / && env -u RUSTUP_TOOLCHAIN rustc "$@"); }

# Refuse anything not this user's, or writable by group or others: the cache
# holds a binary that is about to run with the session's credentials.
private_to_me() {
	[ -O "$1" ] && [ -z "$(find "$1" -maxdepth 0 \( -perm -020 -o -perm -002 \) 2>/dev/null)" ]
}

if command -v rustc >/dev/null 2>&1; then
	if [ -n "${CLOUD_BOOTSTRAP_BUILD_DIR:-}" ]; then
		cache="${CLOUD_BOOTSTRAP_BUILD_DIR}"
	elif [ -n "${XDG_CACHE_HOME:-}" ]; then
		cache="${XDG_CACHE_HOME}/vitruvian-core/cloud-bootstrap"
	elif [ -n "${HOME:-}" ]; then
		cache="${HOME}/.cache/vitruvian-core/cloud-bootstrap"
	else
		# Not /tmp: a shared directory is where someone else plants a binary.
		give_up "HOME is not set, so there is no private place to build the tool; nothing bootstrapped"
	fi
	case "${cache}" in
	/*) ;;
	*) give_up "the build cache must be an absolute path (got '${cache}'); nothing bootstrapped" ;;
	esac
	key="$({ trusted_rustc --version && cat "${src}"/*.rs; } | cksum | tr ' ' '-')"
	bin="${cache}/cloud-bootstrap-${key}"
	(umask 077 && mkdir -p "${cache}") || give_up "cannot create ${cache}; nothing bootstrapped"
	chmod 700 "${cache}" 2>/dev/null
	private_to_me "${cache}" || give_up "refusing to use ${cache}: it is not yours, or others can write to it; nothing bootstrapped"
	if [ -e "${bin}" ] && ! private_to_me "${bin}"; then
		rm -f "${bin}" || give_up "refusing to run ${bin}: it is not yours, or others can write to it; nothing bootstrapped"
	fi
	if [ ! -x "${bin}" ]; then
		log="${cache}/build.log"
		# Built beside the final name and moved into place, so a run that is
		# interrupted, or races another, never leaves a half-written binary.
		if ! trusted_rustc --edition 2021 -o "${bin}.$$" "${src}/main.rs" >"${log}" 2>&1; then
			rm -f "${bin}.$$"
			tail -n 20 "${log}" >&2
			give_up "rustc could not build ${src}/main.rs (full log: ${log}); nothing bootstrapped"
		fi
		mv -f "${bin}.$$" "${bin}" || give_up "cannot write ${bin}; nothing bootstrapped"
		for old in "${cache}"/cloud-bootstrap-*; do
			[ "${old}" = "${bin}" ] || rm -f "${old}"
		done
	fi
	exec "${bin}" "$@"
fi

if command -v bazel >/dev/null 2>&1; then
	case "${sub}" in
	up) target=cloud-bootstrap ;;
	install | auth | whoami | profiles) target="${sub}" ;;
	*)
		printf "cloud-bootstrap: unknown subcommand '%s' (expected: up, install, auth, whoami, profiles)\n" "${sub}" >&2
		exit 2
		;;
	esac
	[ "$#" -gt 0 ] && shift
	cd "${CLOUD_BOOTSTRAP_WORKSPACE}" || give_up "cannot enter ${CLOUD_BOOTSTRAP_WORKSPACE}"
	exec bazel run --noshow_progress "//tools/cloud-bootstrap:${target}" -- "$@"
fi

give_up "neither rustc nor bazel is installed, so the bootstrap cannot run; install rustc (the cloud image ships it) and re-run: bash tools/cloud-bootstrap/cloud-bootstrap.sh ${sub}"
