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
SA_KEY_FILE="$STATE_DIR/sa-key.json"

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
  up         install the profile's CLIs and establish its credentials (default)
  install    CLIs only
  auth       credentials only
  whoami     report what this session has; non-zero if the profile is unsatisfied
  profiles   list the profiles declared in profiles.tsv

Flags:
  --profile <name>  override $VITRUVIAN_PROFILE for this run
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
	out="$("$GCLOUD_BIN" --account="$SA_ACCOUNT" --project="$SA_PROJECT" \
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

authenticate() {
	scrub_placeholder_creds

	if [ "$SA_ACCOUNT" = "-" ]; then
		AUTH_STATE="none"
		note "profile '$PROFILE' declares no GCP identity — no credentials established"
		return 0
	fi

	# Per-profile override first, so ONE environment can hold several profiles'
	# keys and switching $VITRUVIAN_PROFILE switches identity with it.
	# Indirect expansion, not eval: $PROFILE reaches here from an environment
	# variable, and building a variable NAME from it is fine while building shell
	# CODE from it would not be.
	local upper varname key
	upper="$(printf '%s' "$PROFILE" | tr '[:lower:]-' '[:upper:]_')"
	varname="VITRUVIAN_CLOUD_KEY_${upper}"
	key="${!varname:-${VITRUVIAN_CLOUD_KEY:-}}"

	if [ -z "$key" ]; then
		AUTH_STATE="failed"
		warn "VITRUVIAN_CLOUD_KEY is not set — profile '$PROFILE' gets no GCP identity."
		note "add the '$SA_ACCOUNT' service-account key to the cloud environment,"
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
		decode_key "$key" >"$SA_KEY_FILE"
	)
	chmod 600 "$SA_KEY_FILE"

	# IDENTITY PINNING. Assert the key is the account this profile declares before
	# activating it. A key for a DIFFERENT service account is refused rather than
	# used: that is the difference between "the env var was mis-pasted" and "this
	# session silently ran with a broader identity than its label claims".
	local client_email
	client_email="$(key_client_email <"$SA_KEY_FILE")"
	if [ -z "$client_email" ]; then
		AUTH_STATE="failed"
		warn "VITRUVIAN_CLOUD_KEY is not a valid service-account key JSON"
		note "give it as raw JSON or single-line base64, and check it was not truncated"
		rm -f "$SA_KEY_FILE"
		return 1
	fi
	if [ "$client_email" != "$SA_ACCOUNT" ]; then
		AUTH_STATE="failed"
		warn "REFUSING to authenticate: profile '$PROFILE' declares $SA_ACCOUNT"
		note "but VITRUVIAN_CLOUD_KEY belongs to $client_email."
		note "Fix the key or the \$VITRUVIAN_PROFILE on this cloud environment — a key"
		note "for a different account is never used just because it was the one present."
		rm -f "$SA_KEY_FILE"
		return 1
	fi

	if ! "$GCLOUD_BIN" auth activate-service-account --key-file="$SA_KEY_FILE" --quiet >/dev/null 2>&1; then
		AUTH_STATE="failed"
		warn "gcloud could not activate $SA_ACCOUNT (key rejected or revoked)"
		return 1
	fi
	AUTH_STATE="ok"
	"$GCLOUD_BIN" config set project "$SA_PROJECT" --quiet >/dev/null 2>&1

	# GOOGLE_APPLICATION_CREDENTIALS, not a minted access token: an access token
	# expires in an hour and a Claude session outlives that. Pointing at the key
	# file lets every Google client refresh on its own — and it is exactly the
	# "ambient credentials present" case tools/pulumi/pulumi_cmd.sh already
	# documents and honors, so `bazel run //…:preview` works unchanged.
	env_set GOOGLE_APPLICATION_CREDENTIALS "$SA_KEY_FILE"
	env_set CLOUDSDK_CORE_PROJECT "$SA_PROJECT"
	env_set GOOGLE_CLOUD_PROJECT "$SA_PROJECT"
	note "identity: $SA_ACCOUNT (project $SA_PROJECT)"
	return 0
}

materialise_secrets() { # materialise_secrets <comma-list of VAR=secret>
	local pair var name val ambient missing=0
	[ "$1" = "-" ] && return 0
	for pair in $(printf '%s' "$1" | tr ',' ' '); do
		var="${pair%%=*}"
		name="${pair#*=}"
		[ -n "$var" ] && [ -n "$name" ] || continue

		# An env var already set on the cloud environment WINS. That keeps the
		# existing TS_AUTHKEY / LAB_SA_TOKEN wiring working untouched, and is the
		# escape hatch for a profile that has no GCP identity yet.
		#
		# But only when it is actually a credential: the sandbox pre-sets several of
		# these names to placeholder strings, and honoring one of those would pin the
		# session to a token that can never work while suppressing the real fetch.
		ambient="${!var:-}"
		if is_credential "$ambient"; then
			note "$var: already set on the environment (left untouched)"
			continue
		fi
		if [ -n "$ambient" ]; then
			note "$var: ignoring a placeholder value (${#ambient} chars — too short to be a real credential)"
		fi
		unset ambient
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
			note "$var: from $name"
		else
			note "$var: could not read $name from $SA_PROJECT as $SA_ACCOUNT"
			note "  → seed it: bazel run //tools/gcp-secrets:seed -- <infra-dir> $name"
			missing=$((missing + 1))
		fi
		unset val
	done
	return "$missing"
}

# --- report -------------------------------------------------------------------

report() {
	local rc=0 key bin ver pair var
	printf '\nvitruvian-core cloud session — profile %s\n' "${PROFILE:-<unset>}"
	printf '  %s\n\n' "$PURPOSE"

	printf 'tools\n'
	for key in $(printf '%s' "$TOOLS" | tr ',' ' '); do
		[ "$key" = "-" ] && continue
		bin="$key"
		if command -v "$bin" >/dev/null 2>&1; then
			ver="$("$bin" --version 2>/dev/null | head -1)"
			printf '  ✓ %-9s %s\n' "$bin" "${ver:-installed}"
		else
			printf '  ✗ %-9s not installed\n' "$bin"
			rc=1
		fi
	done

	printf '\nidentity\n'
	if [ "$SA_ACCOUNT" = "-" ]; then
		printf '  – none (profile holds no credentials by design)\n'
	elif command -v "$GCLOUD_BIN" >/dev/null 2>&1 &&
		"$GCLOUD_BIN" auth list --filter="status:ACTIVE account:$SA_ACCOUNT" \
			--format="value(account)" 2>/dev/null | grep -q .; then
		printf '  ✓ %s (project %s)\n' "$SA_ACCOUNT" "$SA_PROJECT"
	else
		printf '  ✗ %s — not authenticated\n' "$SA_ACCOUNT"
		rc=1
	fi

	printf '\ncredentials (values never shown)\n'
	if [ "$SECRETS" = "-" ]; then
		printf '  – none\n'
	else
		local val
		for pair in $(printf '%s' "$SECRETS" | tr ',' ' '); do
			var="${pair%%=*}"
			val="${!var:-}"
			if is_credential "$val"; then
				# The LENGTH is the useful signal — it distinguishes a real token from
				# a truncated paste — and it leaks nothing.
				printf '  ✓ %-22s set (%d bytes)\n' "$var" "${#val}"
			elif [ -n "$val" ]; then
				printf '  ✗ %-22s placeholder only (%d bytes; secret %s never resolved)\n' \
					"$var" "${#val}" "${pair#*=}"
				rc=1
			else
				printf '  ✗ %-22s missing (secret %s)\n' "$var" "${pair#*=}"
				rc=1
			fi
			unset val
		done
	fi
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
	printf 'Set VITRUVIAN_PROFILE on the cloud environment to one of:\n\n'
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

PROFILE="${PROFILE_OVERRIDE:-${VITRUVIAN_PROFILE:-${CLAUDE_PROFILE:-}}}"
if [ -z "$PROFILE" ]; then
	warn "VITRUVIAN_PROFILE is not set on this cloud environment — nothing bootstrapped."
	note "There is deliberately no default: a session's capability is a choice, not a"
	note "fallback. Set it to one of:"
	list_profiles "$PROFILES_FILE" >&2
	exit 0
fi

# The profile name is used to build variable names and is echoed into messages,
# so constrain it to what a profile name can actually be. A row can only be
# SELECTED by an exact match anyway; this rejects the input before it is used for
# anything, rather than relying on the manifest to be the only source of truth.
case "$PROFILE" in
*[!a-zA-Z0-9_-]* | "")
	warn "invalid profile name '$PROFILE' (letters, digits, '-' and '_' only)"
	exit 0
	;;
esac

IFS=$'\t' read -r TOOLS SA_ACCOUNT SA_PROJECT SECRETS PURPOSE < <(resolve_profile "$PROFILES_FILE" "$PROFILE") || true
if [ -z "${TOOLS:-}" ]; then
	warn "'$PROFILE' is not a known profile. Known profiles:"
	list_profiles "$PROFILES_FILE" >&2
	exit 0
fi

# Reading the profile's secrets needs gcloud, whatever the tools column says.
# Matched as a whole comma-delimited field (not a substring) so a future
# "gcloud-lite" key could not satisfy the check by accident.
if [ "$SA_ACCOUNT" != "-" ]; then
	case ",$TOOLS," in
	*,gcloud,*) ;;
	*) TOOLS="$TOOLS,gcloud" ;;
	esac
fi

case "$SUBCOMMAND" in
install)
	install_tools "$TOOLS"
	exit 0
	;;
auth)
	authenticate || true
	materialise_secrets "$SECRETS" || true
	wire_session_env
	exit 0
	;;
whoami)
	# Re-apply the session env so a report is about the session, not this shell.
	[ -f "$SESSION_ENV_FILE" ] && . "$SESSION_ENV_FILE"
	report
	exit $?
	;;
up)
	warn "bootstrapping profile '$PROFILE'"
	install_tools "$TOOLS"
	authenticate || true
	materialise_secrets "$SECRETS" || true
	wire_session_env
	report || true
	# Best-effort: never block the session. `whoami` is the gate.
	exit 0
	;;
esac
