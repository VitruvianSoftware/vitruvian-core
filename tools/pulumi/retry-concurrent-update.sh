#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Run a pulumi command, retrying ONLY Pulumi Cloud's account-wide
# concurrent-update 409. Every other failure exits at once with the command's
# own status, unchanged.
#
# Usage:  retry-concurrent-update.sh pulumi <subcommand> [args...]
#
# WHY. The stacks live in one individual Pulumi Cloud account (ipv1337), and an
# individual account runs ONE update at a time ACCOUNT-WIDE: an update on any
# stack rejects an update on any OTHER stack with
#
#   error: [409] Conflict: You have a running update for the stack
#   'tabula-deploy-identity/development'. Your organization does not support
#   concurrent updates.
#
# Each app delivers through its own workflow, so two apps' applies can overlap
# (and jobs inside one run always could: run 37527604456 lost
# tabula-build-stack-shared and oauth-user-inspector-identity-development to
# exactly this). Per-stack GitHub `concurrency:` groups cannot fix it -- the
# constraint spans DIFFERENT stacks -- and a repo-wide group would cancel
# pending runs rather than queue them, silently dropping applies.
#
# The 409 is raised when the update is CREATED, before the engine touches a
# single resource, so retrying it is safe: nothing was applied.
#
# One implementation for every path that runs pulumi: the Bazel wrapper
# (tools/pulumi/pulumi-cmd.sh, which //tools/deploy:cloud-run uses), the
# pulumi-run-captured composite action, and the inline applies in workflows.
#
# Env (all optional):
#   PULUMI_CONFLICT_MAX_ATTEMPTS  total attempts, default 8
#   PULUMI_CONFLICT_RETRY_DELAY   first wait in seconds, doubled per retry, default 15
#   PULUMI_CONFLICT_MAX_DELAY     cap on one wait in seconds, default 60
# The defaults wait up to ~6 minutes in all: room for a few other applies
# (~1-2 minutes each) to finish ahead of this one.
set -uo pipefail

[ "$#" -gt 0 ] || { echo "usage: retry-concurrent-update.sh pulumi <subcommand> [args...]" >&2; exit 2; }

_max="${PULUMI_CONFLICT_MAX_ATTEMPTS:-8}"
_delay="${PULUMI_CONFLICT_RETRY_DELAY:-15}"
_cap="${PULUMI_CONFLICT_MAX_DELAY:-60}"

# BOTH markers required (AND, not OR): a bare "[409] Conflict" is not this
# error, and retrying it would mask a real one.
_is_concurrent_conflict() {
  grep -q '\[409\]' "$1" 2>/dev/null && grep -qiE 'concurrent update' "$1" 2>/dev/null
}

# fd 3 keeps the original stdout, so only stderr goes through the pipe.
exec 3>&1

_attempt=1
while :; do
  _err="$(mktemp)"
  # stderr is tee'd so callers still stream it live (and can tee it again);
  # stdout is untouched. A pipeline, not `2> >(tee ...)`: it waits for tee to
  # finish writing before the file is read, and PIPESTATUS keeps the
  # command's own exit status.
  "$@" 2>&1 1>&3 3>&- | tee "$_err" >&2
  _rc="${PIPESTATUS[0]}"

  if [ "$_rc" -eq 0 ]; then
    rm -f "$_err"
    exit 0
  fi

  if [ "$_attempt" -lt "$_max" ] && _is_concurrent_conflict "$_err"; then
    _wait="$_delay"
    [ "$_wait" -gt "$_cap" ] && _wait="$_cap"
    echo "retry-concurrent-update: attempt ${_attempt}/${_max} hit Pulumi's account-wide concurrent-update 409; retrying in ${_wait}s" >&2
    rm -f "$_err"
    sleep "$_wait"
    _attempt=$((_attempt + 1))
    _delay=$((_delay * 2))
    continue
  fi

  if [ "$_attempt" -ge "$_max" ] && _is_concurrent_conflict "$_err"; then
    echo "retry-concurrent-update: still blocked by another update after ${_max} attempts; giving up." >&2
  fi
  rm -f "$_err"
  exit "$_rc"
done
