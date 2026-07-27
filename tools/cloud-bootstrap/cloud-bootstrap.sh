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

# cloud-bootstrap — make a Claude Code *cloud* sandbox into a working
# vitruvian-core development machine: the repo's CLI tooling, plus exactly the
# credentials the session's PROFILE is allowed to hold.
#
#   bazel run //tools/cloud-bootstrap                 # install + authenticate
#   bazel run //tools/cloud-bootstrap:whoami          # report (gate; non-zero if incomplete)
#   bazel run //tools/cloud-bootstrap:profiles        # list the profiles
#
# It is also the SessionStart hook (.claude/settings.json), which is how it
# actually runs: a cloud session starts as a bare Ubuntu box with git/go/node but
# no bazel, no gh, no gcloud, no pulumi — and no credentials for any of them.
#
# ---------------------------------------------------------------------------
# THE PROFILE IS THE BLAST-RADIUS BOUNDARY
# ---------------------------------------------------------------------------
# $VITRUVIAN_PROFILE (set per cloud environment, alongside the existing
# TS_AUTHKEY / LAB_SA_TOKEN) selects one row of profiles.tsv. That row — not this
# script, and not the agent — decides which CLIs get installed and which secrets
# the session may materialise. A `core` session cannot obtain a Pulumi token or a
# cluster credential even if one exists: its row does not name them, and its
# service account has no IAM to read them.
#
# ---------------------------------------------------------------------------
# WHY TOKEN-BASED, AND WHY EXACTLY ONE CREDENTIAL ON THE ENVIRONMENT
# ---------------------------------------------------------------------------
# The agent, not a human, drives these CLIs, so nothing can rely on an
# interactive `gcloud auth login` / `pulumi login` / `gh auth login` — every
# credential has to be a token the process can present unattended.
#
# The naive way to do that is to paste a token per tool into the cloud
# environment's variables. That does not scale and does not rotate: N long-lived
# secrets, visible to anyone with access to the environment, each rotated by
# hand, in a box whose own UI warns "these are visible to anyone using this
# environment". So instead there is exactly ONE credential on the environment:
#
#   $VITRUVIAN_CLOUD_KEY — the profile's GCP service-account key (raw JSON or
#   base64-of-JSON), whose ONLY permission is `secretmanager.secretAccessor` on
#   that profile's secrets.
#
# Everything else is fetched from Secret Manager at session start, which gives
# the properties that matter:
#   - ONE thing to rotate, in one place, per profile.
#   - Rotating a downstream secret (GitHub PAT, Pulumi token, cluster token)
#     takes effect on the next session with no environment edit at all.
#   - The credential that IS on the environment is worthless on its own: it
#     cannot deploy, cannot read app data, cannot touch a cluster. It can read a
#     named list of secrets and nothing else.
#   - It reuses the mechanism this repo already trusts for exactly this problem
#     (//tools/gcp-secrets seeds them, //tools/saas-cli reads them the same way).
#
# IDENTITY PINNING: the key's `client_email` MUST equal the `sa_account` the
# profile declares. Pasting the `infra` key into an environment labelled `core`
# is refused, loudly, instead of silently handing that session a broader
# identity. This is the same reflex as gcp-identities.tsv — never trust the
# ambient identity, always assert the declared one.
#
# FALLBACK: any env var a profile would materialise that is ALREADY set on the
# environment wins and is left untouched. That is the escape hatch (and how the
# existing TS_AUTHKEY / LAB_SA_TOKEN vars keep working) — no GCP required to get
# started, at the cost of the properties above.
#
# ---------------------------------------------------------------------------
# WHY NOT KEYLESS
# ---------------------------------------------------------------------------
# CI is keyless: GitHub Actions mints an OIDC token and Workload Identity
# Federation exchanges it, so no key exists. A Claude cloud sandbox exposes no
# OIDC issuer we can federate against, so a key is the floor today. profiles.tsv
# is the only thing that would change if that stops being true: swap `sa_account`
# for a WIF provider and no caller moves.
#
# Best-effort by design: a bootstrap hiccup must never block the Claude session,
# so `up`/`install`/`auth` exit 0 on every failure path (mirrors
# tailscale-up.sh / kube-setup.sh) and say loudly what went wrong. `whoami` is
# the opposite — it exits non-zero when the profile is not fully satisfied, so it
# is usable as a gate.
set -uo pipefail

# --- pinned installer versions ----------------------------------------------
# Pinned so a session is reproducible and a surprise major cannot land in the
# middle of an incident — the same reasoning as the neonctl/Squawk pins.
# Override per session with the matching env var.
#
# bazelisk and direnv publish version-less "latest" assets and are deliberately
# taken from those: bazelisk is a launcher whose ONLY job is to honor
# .bazelversion (the pin that actually determines the build), and direnv only
# execs .envrc. Pinning those two would add rot for no reproducibility gain —
# .devcontainer/Dockerfile takes bazelisk the same way.
GH_VERSION="${GH_VERSION:-2.96.0}"
GCLOUD_VERSION="${GCLOUD_VERSION:-577.0.0}"
PULUMI_VERSION="${PULUMI_VERSION:-3.254.0}"
TAILSCALE_VERSION="${TAILSCALE_VERSION:-1.98.9}"
KUBECTL_VERSION="${KUBECTL_VERSION:-}" # empty = resolve dl.k8s.io/release/stable.txt

# A credential shorter than this is a PLACEHOLDER, not a secret.
#
# This is not defensive padding — the sandbox actively pre-sets GH_TOKEN,
# GITHUB_TOKEN, AWS_ACCESS_KEY_ID and CLOUDSDK_AUTH_ACCESS_TOKEN to short dummy
# strings. Without this check the "an env var already set WINS" rule below reads
# those dummies as real credentials: the profile's genuine token is never
# fetched, `gh` fails with a bare 401, and the report cheerfully says ✓. Every
# credential this repo hands a cloud session is comfortably longer — a GitHub PAT
# is 40 chars, a Pulumi token 41, a Tailscale auth key ~60, a ServiceAccount JWT
# ~900, a Google access token 200+ — so the threshold separates the two classes
# with room to spare. Raise it per session if a future secret needs it.
MIN_CREDENTIAL_LEN="${MIN_CREDENTIAL_LEN:-20}"

# --- test seams (real runs get the defaults) ---------------------------------
GCLOUD_BIN="${GCLOUD_BIN:-gcloud}"
INSTALL_DIR="${CLOUD_BOOTSTRAP_INSTALL_DIR:-/usr/local/bin}"
STATE_DIR="${CLOUD_BOOTSTRAP_STATE_DIR:-$HOME/.config/vitruvian-core/cloud}"
BASHRC="${CLOUD_BOOTSTRAP_BASHRC:-$HOME/.bashrc}"

SESSION_ENV_FILE="$STATE_DIR/session.env"

MARK_BEGIN="# >>> vitruvian-core cloud session (managed by tools/cloud-bootstrap) — do not edit by hand"
MARK_END="# <<< vitruvian-core cloud session (managed by tools/cloud-bootstrap)"

warn() { printf 'cloud-bootstrap: %s\n' "$*" >&2; }
note() { printf '  %s\n' "$*" >&2; }

# is_credential <value> — true when the value is long enough to be a real secret.
is_credential() { [ -n "${1:-}" ] && [ "${#1}" -ge "$MIN_CREDENTIAL_LEN" ]; }

# --- workspace + profile resolution ------------------------------------------

if [ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]; then
	WS="$BUILD_WORKSPACE_DIRECTORY"
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
	WS="$CLAUDE_PROJECT_DIR"
else
	WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
PROFILES_FILE="${CLOUD_BOOTSTRAP_PROFILES:-$WS/tools/cloud-bootstrap/profiles.tsv}"
# The build-cache configurator (see configure_build_cache). A path, not a `bazel
# run` target: this runs inside a SessionStart hook, where starting a Bazel
# server to configure Bazel would cost ~25s and nest an invocation inside the
# one the agent is about to make.
CACHE_SETUP="${CLOUD_BOOTSTRAP_CACHE_SETUP:-$WS/tools/remote/setup.sh}"

SUBCOMMAND="${1:-up}"
shift 2>/dev/null || true
FORCE=0
while [ "$#" -gt 0 ]; do
	case "$1" in
	--profile)
		PROFILE_OVERRIDE="${2:-}"
		shift 2
		;;
	--force)
		FORCE=1
		shift
		;;
	-h | --help)
		cat <<'USAGE'
Usage: bazel run //tools/cloud-bootstrap[:<subcommand>] -- [flags]

Subcommands (the sh_binary target bakes one in as $1):
  up         install the profiles' CLIs and establish their credentials (default)
  install    CLIs only
  auth       credentials only
  whoami     report what this session has; non-zero if a profile is unsatisfied
  profiles   list the profiles declared in profiles.tsv

Flags:
  --profile <list>  override $VITRUVIAN_PROFILE for this run (comma-separated)
  --force           run against a local checkout (normally cloud sessions only)
USAGE
		exit 0
		;;
	*)
		warn "ignoring unknown argument '$1'"
		shift
		;;
	esac
done

# load_profile <name> — set the P_* globals from the manifest row, or return 1.
# Globals rather than a return value because a row has five fields and bash 3.2
# (which doctor.sh targets, so the repo's shell floor) has no associative arrays.
load_profile() {
	IFS=$'\t' read -r P_TOOLS P_SA_ACCOUNT P_SA_PROJECT P_SECRETS P_PURPOSE \
		< <(resolve_profile "$PROFILES_FILE" "$1") || true
	[ -n "${P_TOOLS:-}" ] || return 1
	# Reading this profile's secrets needs gcloud, whatever its tools column says.
	# Matched as a whole comma-delimited field (not a substring) so a future
	# "gcloud-lite" key could not satisfy the check by accident.
	if [ "$P_SA_ACCOUNT" != "-" ]; then
		case ",$P_TOOLS," in
		*,gcloud,*) ;;
		*) P_TOOLS="$P_TOOLS,gcloud" ;;
		esac
	fi
	return 0
}

# resolve_profile <file> <name> — emit the row's fields, tab-separated, or nothing.
# Comment/blank/placeholder rows are skipped, exactly like resolve_identity.sh.
# The trailing `purpose` column may contain spaces, so it is rejoined by awk.
resolve_profile() {
	awk -v p="$2" '
    $1 ~ /^#/ { next }
    NF == 0   { next }
    $1 == p {
      purpose = ""
      for (i = 6; i <= NF; i++) purpose = purpose (i > 6 ? " " : "") $i
      printf "%s\t%s\t%s\t%s\t%s\n", $2, $3, $4, $5, purpose
      exit
    }
  ' "$1"
}

list_profiles() {
	awk '
    $1 ~ /^#/ { next }
    NF == 0   { next }
    { purpose = ""
      for (i = 6; i <= NF; i++) purpose = purpose (i > 6 ? " " : "") $i
      printf "  %-10s %s\n", $1, purpose }
  ' "$1"
}

# --- CLI installers -----------------------------------------------------------
# Every installer is idempotent and skips a tool that is already on PATH, so the
# cost after the first session (which the cloud environment snapshots) is a few
# `command -v` calls. Nothing here is version-managed by this script beyond the
# pins above: bazelisk honors .bazelversion, and the repo's own toolchains
# (//tools:bazel_env) own everything else — buildifier, gazelle, aspect,
# addlicense, format, the Go/Node/Python/JVM/Ruby toolchains. This script only
# installs what has to exist BEFORE bazel can run.

priv=()
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
	priv=(sudo)
fi

arch_deb() { case "$(uname -m)" in aarch64 | arm64) echo arm64 ;; *) echo amd64 ;; esac; }
arch_gnu() { case "$(uname -m)" in aarch64 | arm64) echo arm64 ;; *) echo x86_64 ;; esac; }

# fetch_to <url> <dest> — download, or fail with the URL named.
fetch_to() {
	if ! curl -fsSL --retry 3 --retry-delay 2 -o "$2" "$1"; then
		warn "download failed: $1"
		return 1
	fi
}

install_bin() { # install_bin <src> <name>
	chmod +x "$1" && "${priv[@]}" mv "$1" "$INSTALL_DIR/$2"
}

install_bazel() {
	command -v bazel >/dev/null 2>&1 && return 0
	local tmp="${TMPDIR:-/tmp}/bazelisk.$$"
	fetch_to "https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-$(arch_deb)" "$tmp" || return 1
	# Installed under BOTH names: `bazelisk` is what it is, `bazel` is what every
	# doc, BUILD comment and muscle-memory in this repo types. bazelisk then reads
	# .bazelversion, so the version is the repo's, not this script's.
	install_bin "$tmp" bazelisk || return 1
	"${priv[@]}" ln -sf "$INSTALL_DIR/bazelisk" "$INSTALL_DIR/bazel"
}

install_direnv() {
	command -v direnv >/dev/null 2>&1 && return 0
	local tmp="${TMPDIR:-/tmp}/direnv.$$"
	fetch_to "https://github.com/direnv/direnv/releases/latest/download/direnv.linux-$(arch_deb)" "$tmp" || return 1
	install_bin "$tmp" direnv || return 1
	# .envrc puts the //tools:bazel_env bin tree on PATH; without the shell hook
	# it never fires and every tool it exports looks "missing".
	if ! grep -qs 'direnv hook bash' "$BASHRC"; then
		printf '\neval "$(direnv hook bash)"\n' >>"$BASHRC"
	fi
}

install_gh() {
	command -v gh >/dev/null 2>&1 && return 0
	local a tmp dir
	a="$(arch_deb)"
	tmp="${TMPDIR:-/tmp}/gh.$$.tar.gz"
	dir="${TMPDIR:-/tmp}/gh.$$.d"
	fetch_to "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${a}.tar.gz" "$tmp" || return 1
	mkdir -p "$dir" && tar -xzf "$tmp" -C "$dir" --strip-components=1 || return 1
	"${priv[@]}" install -m 0755 "$dir/bin/gh" "$INSTALL_DIR/gh" || return 1
	rm -rf "$tmp" "$dir"
}

install_gcloud() {
	command -v gcloud >/dev/null 2>&1 && return 0
	local a tmp root
	a="$(arch_gnu)"
	tmp="${TMPDIR:-/tmp}/gcloud.$$.tar.gz"
	root="${CLOUD_BOOTSTRAP_GCLOUD_ROOT:-/usr/local}"
	fetch_to "https://storage.googleapis.com/cloud-sdk-release/google-cloud-cli-${GCLOUD_VERSION}-linux-${a}.tar.gz" "$tmp" || return 1
	"${priv[@]}" tar -xzf "$tmp" -C "$root" || return 1
	rm -f "$tmp"
	"${priv[@]}" ln -sf "$root/google-cloud-sdk/bin/gcloud" "$INSTALL_DIR/gcloud"
	"${priv[@]}" ln -sf "$root/google-cloud-sdk/bin/gsutil" "$INSTALL_DIR/gsutil"
}

install_pulumi() {
	command -v pulumi >/dev/null 2>&1 && return 0
	local a tmp dir
	case "$(uname -m)" in aarch64 | arm64) a=arm64 ;; *) a=x64 ;; esac
	tmp="${TMPDIR:-/tmp}/pulumi.$$.tar.gz"
	dir="${TMPDIR:-/tmp}/pulumi.$$.d"
	fetch_to "https://get.pulumi.com/releases/sdk/pulumi-v${PULUMI_VERSION}-linux-${a}.tar.gz" "$tmp" || return 1
	mkdir -p "$dir" && tar -xzf "$tmp" -C "$dir" --strip-components=1 || return 1
	"${priv[@]}" install -m 0755 "$dir"/pulumi* "$INSTALL_DIR/" 2>/dev/null
	rm -rf "$tmp" "$dir"
	command -v pulumi >/dev/null 2>&1
}

install_tailscale() {
	# Both binaries or nothing: tailscale-up.sh runs `tailscaled` (the daemon) and
	# then `tailscale` (the client), so a half-install is worse than none.
	command -v tailscale >/dev/null 2>&1 && command -v tailscaled >/dev/null 2>&1 && return 0
	local a tmp dir
	case "$(uname -m)" in aarch64 | arm64) a=arm64 ;; *) a=amd64 ;; esac
	tmp="${TMPDIR:-/tmp}/tailscale.$$.tgz"
	dir="${TMPDIR:-/tmp}/tailscale.$$.d"
	# The pinned static tarball, not `curl https://tailscale.com/install.sh | sh`:
	# the install script detects the distro and shells out to apt, which drags in a
	# repo + keyring this sandbox does not need and cannot cache as cleanly. The
	# tarball is the same artifact, pinned, and it is the only form that also works
	# on a non-Debian base.
	fetch_to "https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_${a}.tgz" "$tmp" || return 1
	mkdir -p "$dir" && tar -xzf "$tmp" -C "$dir" --strip-components=1 || return 1
	"${priv[@]}" install -m 0755 "$dir/tailscale" "$INSTALL_DIR/tailscale" || return 1
	"${priv[@]}" install -m 0755 "$dir/tailscaled" "$INSTALL_DIR/tailscaled" || return 1
	rm -rf "$tmp" "$dir"
}

install_kubectl() {
	# kube-setup.sh already installs kubectl for the homelab path; this is here so
	# a profile that wants kubectl without the tailnet hooks still gets it.
	command -v kubectl >/dev/null 2>&1 && return 0
	local ver tmp
	ver="${KUBECTL_VERSION:-$(curl -fsSL https://dl.k8s.io/release/stable.txt 2>/dev/null)}"
	[ -n "$ver" ] || {
		warn "could not resolve the stable kubectl version"
		return 1
	}
	tmp="${TMPDIR:-/tmp}/kubectl.$$"
	fetch_to "https://dl.k8s.io/release/${ver}/bin/linux/$(arch_deb)/kubectl" "$tmp" || return 1
	install_bin "$tmp" kubectl
}

install_tools() { # install_tools <comma-list>
	local key rc ok=0 failed=""
	[ "$1" = "-" ] && return 0
	for key in $(printf '%s' "$1" | tr ',' ' '); do
		rc=0
		case "$key" in
		bazel) install_bazel || rc=$? ;;
		direnv) install_direnv || rc=$? ;;
		gh) install_gh || rc=$? ;;
		gcloud) install_gcloud || rc=$? ;;
		pulumi) install_pulumi || rc=$? ;;
		kubectl) install_kubectl || rc=$? ;;
		tailscale) install_tailscale || rc=$? ;;
		*)
			warn "unknown tool key '$key' in profiles.tsv — ignoring"
			continue
			;;
		esac
		if [ "$rc" -eq 0 ]; then ok=$((ok + 1)); else failed="${failed:+$failed }$key"; fi
	done
	[ -n "$failed" ] && warn "install failed for: $failed (the session continues without them)"
	note "installed/verified $ok tool(s)"
	return 0
}

# --- session environment ------------------------------------------------------
# Values land in a 0600 file under $HOME — never in the workspace, where a stray
# `git add -A` would commit them and the secret-scan gate would (rightly) fail
# the push. Two channels carry it into the session because neither is universal:
#   $CLAUDE_ENV_FILE, when the harness provides one; and a marker-delimited block
#   in ~/.bashrc, because every Bash tool call starts a shell from the profile.

env_set() { # env_set <VAR> <value>   (value never echoed)
	# The umask is scoped to a subshell: leaking 077 into the rest of the run
	# would silently change the mode of anything else the session writes.
	(
		umask 077
		mkdir -p "$STATE_DIR"
		chmod 700 "$STATE_DIR" 2>/dev/null
		touch "$SESSION_ENV_FILE"
		chmod 600 "$SESSION_ENV_FILE"
		# Rewrite rather than append-and-last-wins, so a resumed session whose hook
		# runs again does not grow the file a copy at a time.
		grep -v "^export $1=" "$SESSION_ENV_FILE" >"$SESSION_ENV_FILE.tmp" 2>/dev/null || true
		mv "$SESSION_ENV_FILE.tmp" "$SESSION_ENV_FILE"
		chmod 600 "$SESSION_ENV_FILE"
		printf 'export %s=%q\n' "$1" "$2" >>"$SESSION_ENV_FILE"
	)
}

wire_session_env() {
	[ -s "$SESSION_ENV_FILE" ] || return 0
	if ! grep -qs "$MARK_BEGIN" "$BASHRC"; then
		{
			printf '\n%s\n' "$MARK_BEGIN"
			printf '[ -f %q ] && . %q\n' "$SESSION_ENV_FILE" "$SESSION_ENV_FILE"
			printf '%s\n' "$MARK_END"
		} >>"$BASHRC"
	fi
	if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
		cat "$SESSION_ENV_FILE" >>"$CLAUDE_ENV_FILE"
	fi
	# Also apply to THIS process, so the verification below sees them.
	# shellcheck disable=SC1090
	. "$SESSION_ENV_FILE"
}

# --- authentication -----------------------------------------------------------

# scrub_placeholder_creds — the sandbox pre-sets CLOUDSDK_AUTH_ACCESS_TOKEN,
# GH_TOKEN and friends to short placeholder strings. That is worse than unset:
# tools/pulumi/pulumi_cmd.sh treats a non-empty CLOUDSDK_AUTH_ACCESS_TOKEN as
# "ambient credentials present" and deliberately SKIPS the gcp-identities.tsv
# pin, so every `bazel run //…:preview` would then fail against a dummy token
# with a confusing GCP error instead of using the identity we just established.
# A real Google access token is a long `ya29.`-style string; anything short is a
# placeholder. Clearing it restores the intended code path.
scrub_placeholder_creds() {
	local t="${CLOUDSDK_AUTH_ACCESS_TOKEN:-}"
	if [ -n "$t" ] && ! is_credential "$t"; then
		env_set CLOUDSDK_AUTH_ACCESS_TOKEN ""
		note "cleared a placeholder CLOUDSDK_AUTH_ACCESS_TOKEN (would have masked the real identity)"
	fi
}

# decode_key — $VITRUVIAN_CLOUD_KEY as raw JSON or base64-of-JSON, on stdout.
# Same tolerance as kube-setup.sh's CLAUDE_SSH_KEY handling: a pasted credential
# arrives wrapped, CR-laden, or base64'd depending on who pasted it.
decode_key() {
	local raw="$1"
	if printf '%s' "$raw" | tr -d '[:space:]' | head -c 1 | grep -q '{'; then
		printf '%s' "$raw" | tr -d '\r'
	else
		printf '%s' "$raw" | tr -d '[:space:]' | base64 -d 2>/dev/null
	fi
}

# key_client_email — the key's `client_email` on stdout, from stdin.
#
# Deliberately not jq: this runs before anything is installed, in a sandbox whose
# tool set we do not control, and a missing jq must not turn the identity CHECK
# into a skipped check. `client_email` is a flat string field in a
# service-account key, so a scoped extraction is sufficient and has no
# dependencies. Emits nothing unless exactly one match is found — a malformed or
# doctored key yields empty, which the caller treats as fatal.
key_client_email() {
	awk '
    match($0, /"client_email"[[:space:]]*:[[:space:]]*"[^"]*"/) {
      s = substr($0, RSTART, RLENGTH)
      sub(/^"client_email"[[:space:]]*:[[:space:]]*"/, "", s)
      sub(/"$/, "", s)
      n++; last = s
    }
    END { if (n == 1) print last }
  '
}

# gcloud_secret <name> — the value on stdout, or non-zero with the reason.
#
# gcloud EXITS 0 while printing "ERROR: … Reauthentication failed" to stderr on a
# broken credential, so neither the status code nor an empty result can be
# trusted alone (the same trap //tools/saas-cli and //tools/gcp-secrets guard).
gcloud_secret() {
	local name="$1" out rc err
	err="$(mktemp)"
	out="$("$GCLOUD_BIN" --account="$P_SA_ACCOUNT" --project="$P_SA_PROJECT" \
		secrets versions access latest --secret="$name" 2>"$err")" && rc=0 || rc=$?
	if [ "$rc" -ne 0 ] || grep -q '^ERROR:' "$err" 2>/dev/null || [ -z "$out" ]; then
		sed 's/^/    /' "$err" >&2
		rm -f "$err"
		return 1
	fi
	rm -f "$err"
	printf '%s' "$out"
}

# AUTH_STATE gates every later secret read: 'ok' (identity established), 'none'
# (the profile declares none), or 'failed'. It exists so a refusal FAILS CLOSED —
# without it, `authenticate || true` would carry on to materialise_secrets and
# the only thing stopping a rejected session from reading secrets would be gcloud
# itself returning an error. Authorisation must not be delegated to the failure
# mode of the tool we just refused to trust.
AUTH_STATE="none"

# PRIMARY_ACCOUNT is the identity that becomes AMBIENT for the session --
# GOOGLE_APPLICATION_CREDENTIALS, CLOUDSDK_CORE_PROJECT, and therefore what
# `pulumi`, `gsutil` and a bare `gcloud` use. With several profiles active only
# one can hold that slot, so the rule is deliberate and dumb: THE FIRST LISTED
# PROFILE THAT HAS AN IDENTITY WINS. Every other profile's account is still
# activated in gcloud and still reads its OWN secrets via an explicit --account,
# so the blast-radius boundary is unchanged -- it is only the default that is
# first-listed. Order the list to put the identity you want ambient first.
PRIMARY_ACCOUNT=""

authenticate() { # authenticate <profile>
	local profile="$1"
	scrub_placeholder_creds

	if [ "$P_SA_ACCOUNT" = "-" ]; then
		AUTH_STATE="none"
		note "profile '$profile' declares no GCP identity — no credentials established"
		return 0
	fi

	# Per-profile override first, so ONE environment can hold several profiles'
	# keys and switching $VITRUVIAN_PROFILE switches identity with it.
	# Indirect expansion, not eval: $PROFILE reaches here from an environment
	# variable, and building a variable NAME from it is fine while building shell
	# CODE from it would not be.
	local upper varname key sa_key_file
	upper="$(printf '%s' "$profile" | tr '[:lower:]-' '[:upper:]_')"
	varname="VITRUVIAN_CLOUD_KEY_${upper}"
	key="${!varname:-${VITRUVIAN_CLOUD_KEY:-}}"
	# One file per profile: several identities can be active at once, and the
	# primary's path is what GOOGLE_APPLICATION_CREDENTIALS points at for the whole
	# session, so they must not overwrite each other.
	sa_key_file="$STATE_DIR/sa-key-${profile}.json"

	if [ -z "$key" ]; then
		AUTH_STATE="failed"
		warn "no key for profile '$profile' (\$$varname or \$VITRUVIAN_CLOUD_KEY) — no GCP identity."
		note "add the '$P_SA_ACCOUNT' service-account key to the cloud environment,"
		note "or set the individual tokens directly (they are honored if already present)."
		return 0
	fi

	if ! command -v "$GCLOUD_BIN" >/dev/null 2>&1; then
		AUTH_STATE="failed"
		warn "gcloud is not installed — cannot establish the profile identity"
		return 0
	fi

	mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"
	(
		umask 077
		decode_key "$key" >"$sa_key_file"
	)
	chmod 600 "$sa_key_file"

	# IDENTITY PINNING. Assert the key is the account this profile declares before
	# activating it. A key for a DIFFERENT service account is refused rather than
	# used: that is the difference between "the env var was mis-pasted" and "this
	# session silently ran with a broader identity than its label claims".
	local client_email
	client_email="$(key_client_email <"$sa_key_file")"
	if [ -z "$client_email" ]; then
		AUTH_STATE="failed"
		warn "the key for profile '$profile' is not a valid service-account key JSON"
		note "give it as raw JSON or single-line base64, and check it was not truncated"
		rm -f "$sa_key_file"
		return 1
	fi
	if [ "$client_email" != "$P_SA_ACCOUNT" ]; then
		AUTH_STATE="failed"
		warn "REFUSING to authenticate: profile '$profile' declares $P_SA_ACCOUNT"
		note "but \$$varname resolved to a key belonging to $client_email."
		note "With several profiles active each needs its OWN key in \$VITRUVIAN_CLOUD_KEY_<PROFILE>;"
		note "the shared \$VITRUVIAN_CLOUD_KEY can only satisfy one of them."
		rm -f "$sa_key_file"
		return 1
	fi

	if ! "$GCLOUD_BIN" auth activate-service-account --key-file="$sa_key_file" --quiet >/dev/null 2>&1; then
		AUTH_STATE="failed"
		warn "gcloud could not activate $P_SA_ACCOUNT (key rejected or revoked)"
		return 1
	fi
	AUTH_STATE="ok"

	# GOOGLE_APPLICATION_CREDENTIALS, not a minted access token: an access token
	# expires in an hour and a Claude session outlives that. Pointing at the key
	# file lets every Google client refresh on its own — and it is exactly the
	# "ambient credentials present" case tools/pulumi/pulumi_cmd.sh already
	# documents and honors, so `bazel run //…:preview` works unchanged.
	if [ -z "$PRIMARY_ACCOUNT" ]; then
		PRIMARY_ACCOUNT="$P_SA_ACCOUNT"
		"$GCLOUD_BIN" config set project "$P_SA_PROJECT" --quiet >/dev/null 2>&1
		env_set GOOGLE_APPLICATION_CREDENTIALS "$sa_key_file"
		env_set CLOUDSDK_CORE_PROJECT "$P_SA_PROJECT"
		env_set GOOGLE_CLOUD_PROJECT "$P_SA_PROJECT"
		note "identity: $P_SA_ACCOUNT (project $P_SA_PROJECT) — PRIMARY, ambient for pulumi/gcloud"
	else
		note "identity: $P_SA_ACCOUNT (project $P_SA_PROJECT) — reads its own secrets only"
	fi
	return 0
}

# CLAIMED records every VAR=secret pair already materialised, as " VAR=name ...".
# With several profiles active, two rows can name the same env var. Identical
# mappings are a harmless overlap (every profile wants the same GH_TOKEN);
# DIFFERING ones are a misconfiguration where "which token did this session
# actually get?" would depend on manifest row order, so they are refused. A flat
# string, not an associative array, to stay bash 3.2-safe.
CLAIMED=""

materialise_secrets() { # materialise_secrets <profile>
	local profile="$1" pair var name val ambient claimed_as missing=0
	[ "$P_SECRETS" = "-" ] && return 0
	for pair in $(printf '%s' "$P_SECRETS" | tr ',' ' '); do
		var="${pair%%=*}"
		name="${pair#*=}"
		[ -n "$var" ] && [ -n "$name" ] || continue

		# Already claimed by an earlier profile in the list?
		case "$CLAIMED" in
		*" $var="*)
			claimed_as="${CLAIMED##*" $var="}"
			claimed_as="${claimed_as%% *}"
			if [ "$claimed_as" = "$name" ]; then
				continue # same mapping, already done
			fi
			warn "REFUSING $var for profile '$profile': an earlier profile already mapped it"
			note "to secret '$claimed_as', this one says '$name'. Which credential the"
			note "session holds must not depend on manifest row order — fix the manifest."
			missing=$((missing + 1))
			continue
			;;
		esac

		# An env var already set on the cloud environment WINS. That keeps the
		# existing TS_AUTHKEY / LAB_SA_TOKEN wiring working untouched, and is the
		# escape hatch for a profile that has no GCP identity yet.
		#
		# But only when it is actually a credential: the sandbox pre-sets several of
		# these names to placeholder strings, and honoring one of those would pin the
		# session to a token that can never work while suppressing the real fetch.
		ambient="${!var:-}"
		if is_credential "$ambient"; then
			CLAIMED="$CLAIMED $var=$name"
			note "$var: already set on the environment (left untouched)"
			continue
		fi
		if [ -n "$ambient" ]; then
			note "$var: ignoring a placeholder value (${#ambient} chars — too short to be a real credential)"
		fi
		unset ambient
		# ENVIRONMENT-ONLY credential (secret name "-"). Some credentials are not in
		# Secret Manager and never will be: BUILDBUDDY_API_KEY is a GitHub
		# Actions/Dependabot secret owned by //infrastructure/pulumi/platform/repo_config
		# and injected from the pipeline. Naming a Secret Manager entry for it would
		# be a wrong address that fails the day Secret Manager is actually wired up.
		# Declaring it with "-" keeps it INSIDE the profile boundary — a profile that
		# does not list it still gets it scrubbed — while never attempting a read.
		if [ "$name" = "-" ]; then
			note "$var: environment-only (not in Secret Manager by design)"
			missing=$((missing + 1))
			continue
		fi

		# FAIL CLOSED. Anything other than an established identity means no read is
		# attempted at all — a refused or broken credential must not be handed to
		# gcloud "to see what happens".
		if [ "$AUTH_STATE" != "ok" ]; then
			note "$var: unavailable (no established GCP identity to read $name with)"
			missing=$((missing + 1))
			continue
		fi
		if val="$(gcloud_secret "$name")"; then
			env_set "$var" "$val"
			CLAIMED="$CLAIMED $var=$name"
			note "$var: from $name (as $P_SA_ACCOUNT)"
		else
			note "$var: could not read $name from $P_SA_PROJECT as $P_SA_ACCOUNT"
			note "  → seed it: bazel run //tools/gcp-secrets:seed -- <infra-dir> $name"
			missing=$((missing + 1))
		fi
		unset val
	done
	return "$missing"
}

# known_credential_vars — every env var named in ANY row's secrets column.
#
# The manifest defines what counts as a credential, so this stays correct as
# rows are added and never needs a hardcoded list to drift.
known_credential_vars() {
	awk '
    $1 ~ /^#/ { next }
    NF == 0   { next }
    {
      n = split($5, pairs, ",")
      for (i = 1; i <= n; i++) {
        split(pairs[i], kv, "=")
        if (kv[1] != "" && kv[1] != "-") print kv[1]
      }
    }
  ' "$PROFILES_FILE" | sort -u
}

# scrub_undeclared — blank every manifest-declared credential the active
# profile(s) did NOT claim.
#
# WITHOUT THIS THE PROFILE BOUNDARY IS DECORATIVE whenever credentials come from
# the environment rather than Secret Manager. The bootstrap only ever ADDS, so a
# `readonly` session -- whose entire purpose is to be the one that CANNOT reach
# production -- would still read a Pulumi token or a cluster credential straight
# out of the environment while :whoami cheerfully reported "creds – none".
#
# Scope, honestly: this blanks the vars for shells that source session.env, which
# is every Bash tool call the agent makes -- the surface that matters. It cannot
# unset them from the harness's own process environment. And it only covers
# credentials THE MANIFEST NAMES; a narrow profile is a smaller blast radius, not
# a sandbox.
scrub_undeclared() {
	local var cleared=0
	for var in $(known_credential_vars); do
		case "$CLAIMED" in
		*" $var="*) continue ;; # an active profile claimed it
		esac
		[ -n "${!var:-}" ] || continue
		env_set "$var" ""
		note "$var: CLEARED — no active profile declares it"
		cleared=$((cleared + 1))
	done
	[ "$cleared" -eq 0 ] || note "scrubbed $cleared credential(s) this profile is not entitled to"
}

# --- build cache --------------------------------------------------------------

# configure_build_cache — make a plain `bazel` in this session read and write the
# shared BuildBuddy cache.
#
# WHY THIS IS NOT COSMETIC: the config that enables the cache lives in
# user.bazelrc, which is git-ignored — so a freshly cloned sandbox has NO cache
# configuration at all. The session then cold-builds a large polyglot repo on a
# 4-core box while holding a perfectly good BUILDBUDDY_API_KEY it never uses. A
# developer gets this from `bazel run //tools/remote:setup`; a cloud session has
# nobody to run it, which is precisely why it belongs here.
#
# DELEGATES to that same script rather than writing the block itself, so there is
# ONE definition of what the block contains and one place that keeps user.bazelrc
# out of git. (That script also guards the committed tools/remote.bazelrc, so
# this does not dirty the working tree.)
#
# THE KEY TRAVELS IN THE ENVIRONMENT, NEVER AS `--key`: argv is world-readable
# through `ps`. Same reflex as the service-account key, which travels as
# --key-file for the same reason.
#
# CACHE ONLY — never --config=remote. Full RBE sets
# --remote_download_outputs=minimal and cannot run macOS targets, so making it
# the default would break `bazel run` of local tools (this script's own targets
# included) and every lane that consumes bazel-bin directly. RBE stays an
# explicit opt-in, exactly as it is on a laptop.
#
# CALLED FROM `auth`, NEVER FROM `install`. The block written to user.bazelrc
# contains the API key, and `install` is the phase the cloud environment's Setup
# script bakes into a cached image — writing it there would bake a credential
# into a snapshot, the one thing that phase must never do.
configure_build_cache() {
	# Entitlement first: CLAIMED means an ACTIVE profile declared this var and it
	# resolved to a real credential. A profile that does not name it has already
	# had it scrubbed, and must not get cache write access by the back door.
	case "$CLAIMED" in
	*" BUILDBUDDY_API_KEY="*) ;;
	*) return 0 ;;
	esac
	# Re-checked rather than trusted: the sandbox pre-sets several credential
	# names to short placeholders, and configuring a cache with one would produce
	# a config that looks enabled and authenticates against nothing.
	is_credential "${BUILDBUDDY_API_KEY:-}" || return 0
	case ",$TOOLS_ALL," in
	*,bazel,*) ;;
	*) return 0 ;; # nothing in this session would read user.bazelrc
	esac
	if [ ! -x "$CACHE_SETUP" ]; then
		note "build cache: $CACHE_SETUP is not executable — skipped, builds stay local"
		return 0
	fi
	# BUILD_WORKSPACE_DIRECTORY pins where user.bazelrc lands: the configurator
	# otherwise falls back to `git rev-parse` and then to $PWD, and a hook's cwd is
	# not guaranteed to be the workspace.
	if BUILD_WORKSPACE_DIRECTORY="$WS" \
		BUILDBUDDY_API_KEY="$BUILDBUDDY_API_KEY" \
		"$CACHE_SETUP" --cache buildbuddy --no-ci --yes >/dev/null 2>&1; then
		note "build cache: BuildBuddy is now the default for plain bazel (cache only; RBE stays --config=remote)"
	else
		note "build cache: could not configure — builds stay local"
	fi
}

# --- report -------------------------------------------------------------------

report() {
	local rc=0 key bin ver pair var val profile

	printf '\nvitruvian-core cloud session — profile(s): %s\n\n' "${PROFILE_LIST:-<unset>}"

	printf 'tools\n'
	for key in $(printf '%s' "$TOOLS_ALL" | tr ',' ' '); do
		[ "$key" = "-" ] && continue
		bin="$key"
		if command -v "$bin" >/dev/null 2>&1; then
			ver="$("$bin" --version 2>/dev/null | head -1)"
			printf '  ✓ %-10s %s\n' "$bin" "${ver:-installed}"
		else
			printf '  ✗ %-10s not installed\n' "$bin"
			rc=1
		fi
	done

	# Reported on the BEHAVIOUR (is a plain `bazel` pointed at the shared cache?)
	# rather than on the marker comment, which belongs to another script and can
	# be renamed without changing what the session actually does.
	#
	# SAYS "configured", NOT "working", AND THAT IS THE HONEST CLAIM: the key's
	# validity cannot be established without a network round trip, and a wrong one
	# fails SILENTLY -- Bazel treats remote-cache auth errors as warnings and
	# builds locally, so a session degrades to cold builds while looking fine.
	# Worse, the BES upload is async, so the giveaway
	# (`UNAUTHENTICATED: Invalid API key`) surfaces on the NEXT invocation, not the
	# one that failed. Length alone cannot catch it: a 20-byte key passes
	# is_credential and can still be rejected. If builds are slow, check the
	# warnings before trusting this line.
	#
	# Deliberately does NOT set rc: `whoami` is the gate for "this profile got the
	# tools and credentials it declares", and a cold cache is a slow session, not
	# an unsatisfied profile.
	case ",$TOOLS_ALL," in
	*,bazel,*)
		if grep -qs -- '--config=remotecache' "$WS/user.bazelrc"; then
			printf '  ✓ %-10s BuildBuddy configured for plain bazel (cache only)\n' "cache"
		else
			printf '  – %-10s not configured — every build is cold and local\n' "cache"
		fi
		;;
	esac

	# Per profile, because that is the boundary being reported on: which identity
	# holds which credentials. A merged list would hide exactly the thing the
	# profile split exists to make visible.
	for profile in $PROFILE_LIST; do
		load_profile "$profile" || continue
		printf '\n%s — %s\n' "$profile" "$P_PURPOSE"

		if [ "$P_SA_ACCOUNT" = "-" ]; then
			printf '  identity   – none (holds no credentials by design)\n'
		elif command -v "$GCLOUD_BIN" >/dev/null 2>&1 &&
			"$GCLOUD_BIN" auth list --filter="status:ACTIVE account:$P_SA_ACCOUNT" \
				--format="value(account)" 2>/dev/null | grep -q .; then
			if [ "$P_SA_ACCOUNT" = "${PRIMARY_ACCOUNT:-}" ]; then
				printf '  identity   ✓ %s (project %s) [primary]\n' "$P_SA_ACCOUNT" "$P_SA_PROJECT"
			else
				printf '  identity   ✓ %s (project %s)\n' "$P_SA_ACCOUNT" "$P_SA_PROJECT"
			fi
		else
			printf '  identity   ✗ %s — not authenticated\n' "$P_SA_ACCOUNT"
			rc=1
		fi

		if [ "$P_SECRETS" = "-" ]; then
			printf '  creds      – none\n'
		else
			for pair in $(printf '%s' "$P_SECRETS" | tr ',' ' '); do
				var="${pair%%=*}"
				val="${!var:-}"
				if is_credential "$val"; then
					# The LENGTH is the useful signal — it distinguishes a real token from
					# a truncated paste — and it leaks nothing.
					printf '  creds      ✓ %-22s set (%d bytes)\n' "$var" "${#val}"
				elif [ -n "$val" ]; then
					printf '  creds      ✗ %-22s placeholder only (%d bytes; %s never resolved)\n' \
						"$var" "${#val}" "${pair#*=}"
					rc=1
				else
					printf '  creds      ✗ %-22s missing (secret %s)\n' "$var" "${pair#*=}"
					rc=1
				fi
				unset val
			done
		fi
	done
	printf '\n'
	return "$rc"
}

# --- main ---------------------------------------------------------------------

case "$SUBCOMMAND" in
profiles)
	[ -f "$PROFILES_FILE" ] || {
		warn "profile manifest not found: $PROFILES_FILE"
		exit 1
	}
	printf 'Set VITRUVIAN_PROFILE on the cloud environment to one, or several\n'
	printf 'comma-separated (e.g. VITRUVIAN_PROFILE=core,homelab):\n\n'
	list_profiles "$PROFILES_FILE"
	exit 0
	;;
up | install | auth | whoami) ;;
*)
	warn "unknown subcommand '$SUBCOMMAND' (expected: up, install, auth, whoami, profiles)"
	exit 2
	;;
esac

# Cloud sessions only — a local checkout already has direnv + bazel_env and real
# gcloud credentials, and must not have a service-account key installed over
# them. `--force` is the deliberate override for testing this script locally.
if [ "$SUBCOMMAND" != "whoami" ] && [ "$FORCE" -eq 0 ] && [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
	warn "not a cloud session (CLAUDE_CODE_REMOTE != true) — nothing to do."
	note "pass --force to run this against a local checkout anyway."
	exit 0
fi

[ -f "$PROFILES_FILE" ] || {
	warn "profile manifest not found: $PROFILES_FILE"
	exit 0
}

PROFILE_RAW="${PROFILE_OVERRIDE:-${VITRUVIAN_PROFILE:-${CLAUDE_PROFILE:-}}}"
if [ -z "$PROFILE_RAW" ]; then
	warn "VITRUVIAN_PROFILE is not set on this cloud environment — nothing bootstrapped."
	note "There is deliberately no default: a session's capability is a choice, not a"
	note "fallback. Set it to one or more (comma-separated) of:"
	list_profiles "$PROFILES_FILE" >&2
	exit 0
fi

# Several profiles may be combined: VITRUVIAN_PROFILE=core,homelab unions their
# tools and their secrets. Each keeps its OWN service account and reads only its
# OWN secrets, so combining does not merge privileges into one identity — it just
# gives the session two of them. The FIRST listed profile with an identity is the
# primary (see PRIMARY_ACCOUNT), so order the list accordingly.
#
# Deduped preserving order, and validated per name: a name reaches variable
# construction and messages, so it is constrained at the door rather than trusted
# because the manifest is "the only source of truth".
PROFILE_LIST=""
for _p in $(printf '%s' "$PROFILE_RAW" | tr ',' ' '); do
	case "$_p" in
	*[!a-zA-Z0-9_-]* | "")
		warn "invalid profile name '$_p' (letters, digits, '-' and '_' only)"
		exit 0
		;;
	esac
	case " $PROFILE_LIST " in
	*" $_p "*) continue ;; # already listed
	esac
	if ! load_profile "$_p"; then
		warn "'$_p' is not a known profile. Known profiles:"
		list_profiles "$PROFILES_FILE" >&2
		exit 0
	fi
	PROFILE_LIST="${PROFILE_LIST:+$PROFILE_LIST }$_p"
done

if [ -z "$PROFILE_LIST" ]; then
	warn "no usable profile in '$PROFILE_RAW' — nothing bootstrapped."
	exit 0
fi

# Union of every listed profile's tools, for a single install pass.
TOOLS_ALL=""
for _p in $PROFILE_LIST; do
	load_profile "$_p" || continue
	for _t in $(printf '%s' "$P_TOOLS" | tr ',' ' '); do
		[ "$_t" = "-" ] && continue
		case ",$TOOLS_ALL," in
		*",$_t,"*) continue ;;
		esac
		TOOLS_ALL="${TOOLS_ALL:+$TOOLS_ALL,}$_t"
	done
done
[ -n "$TOOLS_ALL" ] || TOOLS_ALL="-"

# establish_credentials — authenticate and materialise EVERY listed profile, each
# with its own identity. Ordered by PROFILE_LIST so the primary and any secret
# conflict resolve predictably.
establish_credentials() {
	local _p
	for _p in $PROFILE_LIST; do
		load_profile "$_p" || continue
		authenticate "$_p" || true
		materialise_secrets "$_p" || true
	done
	# AFTER every profile has claimed what it is entitled to, so the scrub can
	# tell "nobody declared this" from "not reached yet".
	scrub_undeclared
	wire_session_env
	# AFTER wire_session_env, which sources session.env into this process — that
	# is what puts a Secret-Manager-sourced BUILDBUDDY_API_KEY in scope here (one
	# taken from the environment is already in scope).
	configure_build_cache
}

case "$SUBCOMMAND" in
install)
	install_tools "$TOOLS_ALL"
	exit 0
	;;
auth)
	establish_credentials
	exit 0
	;;
whoami)
	# Re-apply the session env so a report is about the session, not this shell.
	[ -f "$SESSION_ENV_FILE" ] && . "$SESSION_ENV_FILE"
	# `whoami` does not authenticate, so recover which identity ended up ambient
	# from gcloud itself rather than leaving the [primary] marker blank.
	if command -v "$GCLOUD_BIN" >/dev/null 2>&1; then
		PRIMARY_ACCOUNT="$("$GCLOUD_BIN" config get-value account 2>/dev/null)"
		[ "$PRIMARY_ACCOUNT" = "(unset)" ] && PRIMARY_ACCOUNT=""
	fi
	report
	exit $?
	;;
up)
	warn "bootstrapping profile(s): $PROFILE_LIST"
	install_tools "$TOOLS_ALL"
	establish_credentials
	report || true
	# Best-effort: never block the session. `whoami` is the gate.
	exit 0
	;;
esac
