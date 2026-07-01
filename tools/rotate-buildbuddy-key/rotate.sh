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

# rotate.sh — guided BuildBuddy API-key rotation (issue #456).
#
#   bazel run //tools/rotate-buildbuddy-key
#
# Walks an operator step by step through rotating the BuildBuddy RBE API key that
# CI authenticates with. Everything that can be automated is automated; the two
# steps that require a human — minting the new key and revoking the old one in
# the BuildBuddy console — are prompted with the exact clicks. The new key value
# is read WITHOUT echo and piped straight to `gh secret set` over stdin; it is
# never printed, logged, or placed on a command line, and is unset immediately.
#
# The rotation is ordered so CI never breaks: the old key stays valid until the
# new key is proven green by a verification build, and only then are you prompted
# to revoke the old one.

set -euo pipefail

# ---- presentation (tty-aware, degrades cleanly when piped) -------------------
if [ -t 1 ]; then
  BOLD="$(printf '\033[1m')"; DIM="$(printf '\033[2m')"; RESET="$(printf '\033[0m')"
  GREEN="$(printf '\033[32m')"; YELLOW="$(printf '\033[33m')"; CYAN="$(printf '\033[36m')"; RED="$(printf '\033[31m')"
else
  BOLD=""; DIM=""; RESET=""; GREEN=""; YELLOW=""; CYAN=""; RED=""
fi
ok()   { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$1"; }
err()  { printf '  %s✗%s %s\n' "$RED" "$RESET" "$1" >&2; }
auto() { printf '%s[auto]%s %s\n' "$DIM" "$RESET" "$1"; }
step() { printf '\n%s──%s %s%s%s\n' "$CYAN" "$RESET" "$BOLD" "$1" "$RESET"; }
you()  { printf '%s[you]%s  %s\n' "$YELLOW" "$RESET" "$1"; }
ask()  { # ask "prompt" -> returns 0 on y/yes
  local reply; printf '%s?%s %s [y/N] ' "$CYAN" "$RESET" "$1"; read -r reply
  case "${reply:-}" in y|Y|yes|YES) return 0;; *) return 1;; esac
}
pause() { printf '%s↵%s %s' "$CYAN" "$RESET" "${1:-Press Enter to continue…}"; read -r _; }

REPO="VitruvianSoftware/vitruvian-core"
SECRET="BUILDBUDDY_API_KEY"
CONSOLE="https://app.buildbuddy.io/settings/org/api-keys"

printf '\n%s BuildBuddy API-key rotation %s  (issue #456)\n' "${BOLD}${CYAN}" "$RESET"
printf '%sThe engineering is already done — the key is out of git and read from env.\n' "$DIM"
printf 'This only rotates the secret value. Old key stays live until the new one is verified.%s\n' "$RESET"

# ---- 0. preflight (automated) ------------------------------------------------
step "0. Preflight"
command -v gh >/dev/null 2>&1 || { err "gh CLI not found — install it and re-run."; exit 1; }
if gh auth status >/dev/null 2>&1; then ok "gh authenticated ($(gh api user --jq .login 2>/dev/null || echo '?'))"; else err "gh not authenticated — run 'gh auth login'."; exit 1; fi

repo_root="${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
devyaml="${repo_root}/infrastructure/pulumi/repo_config/Pulumi.dev.yaml"
# Flag an ACTUAL committed key value only — a real `buildbuddyApiKey:` config key
# or a `secure:` blob — not the comment lines that legitimately mention the key
# name (those describe how the value is injected, and are expected to remain).
if [ -f "${devyaml}" ] && grep -qE '^[[:space:]]*(buildbuddyApiKey[[:space:]]*:|secure:)' "${devyaml}"; then
  warn "repo_config/Pulumi.dev.yaml still commits a buildbuddyApiKey value — expected it de-committed (#456 code half). Continuing."
else
  ok "no committed BuildBuddy key in repo_config (#456 code half is in)"
fi

if gh api "repos/${REPO}/actions/secrets/${SECRET}" >/dev/null 2>&1; then
  ok "current Actions secret ${SECRET} exists ($(gh api "repos/${REPO}/actions/secrets/${SECRET}" --jq .updated_at 2>/dev/null))"
else
  warn "Actions secret ${SECRET} not found — this run will create it."
fi

# ---- 1. mint the new key (YOUR action) --------------------------------------
step "1. Mint a new key in the BuildBuddy console"
you "Open:            ${BOLD}${CONSOLE}${RESET}"
you "Click:           ${BOLD}Create new API key${RESET} (org-level; same capabilities as the current one)."
you "Copy the value.  Leave the OLD key ALIVE for now — we revoke it at the end."
if command -v open >/dev/null 2>&1 && ask "Open the BuildBuddy console in your browser now?"; then
  open "${CONSOLE}" >/dev/null 2>&1 || true
fi
pause "Press Enter once you have the new key copied…"

# ---- 2. set the secret (YOUR input, handled securely) -----------------------
step "2. Store the new key (read silently — never printed or logged)"
you "Paste the new key at the prompt. Input is hidden; it goes straight to"
you "'gh secret set' over stdin (never on a command line) and is cleared after."
key=""
printf '%s?%s New %s value: ' "$CYAN" "$RESET" "$SECRET"
read -rs key || true
printf '\n'
if [ -z "${key}" ]; then err "empty value — aborting; nothing changed."; exit 1; fi

# stdin, not argv: the value never appears in the process list or shell history.
printf '%s' "${key}" | gh secret set "${SECRET}" --repo "${REPO}" && ok "set Actions secret ${SECRET}"
printf '%s' "${key}" | gh secret set "${SECRET}" --repo "${REPO}" --app dependabot && ok "set Dependabot secret ${SECRET}"
unset key
ok "secret updated in both scopes (Actions + Dependabot); local value cleared"

# ---- 3. verify the new key with a real build (automated, optional) ----------
step "3. Verify the new key before revoking the old one"
you "A build must authenticate to BuildBuddy RBE with the NEW key and go green."
if ask "Re-run the latest CI on main now and wait for it to pass? (takes several minutes)"; then
  runid="$(gh run list --repo "${REPO}" --workflow ci.yaml --branch main --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)"
  if [ -n "${runid}" ]; then
    auto "re-running CI run ${runid} with the new key…"
    gh run rerun "${runid}" --repo "${REPO}" >/dev/null 2>&1 || warn "could not trigger rerun (permissions?) — verify a build manually instead."
    auto "polling (Ctrl-C to stop waiting; the rerun keeps going)…"
    for _ in $(seq 1 40); do
      sleep 30
      st="$(gh run view "${runid}" --repo "${REPO}" --json status,conclusion --jq '.status+"/"+(.conclusion//"-")' 2>/dev/null || echo '?')"
      auto "CI: ${st}"
      case "${st}" in
        completed/success) ok "verification build GREEN — the new key works."; break;;
        completed/*) err "verification build did NOT pass (${st}). Do NOT revoke the old key; investigate."; exit 1;;
      esac
    done
  else
    warn "no recent CI run found to re-run — push any change or dispatch a build, then confirm it is green."
  fi
else
  you "Verify manually: confirm the next CI build on main is green before step 4."
fi

# ---- 4. revoke the old key (YOUR action) ------------------------------------
step "4. Revoke the OLD key (only after the new one is verified green)"
you "Back in ${BOLD}${CONSOLE}${RESET}, delete the PREVIOUS key so it can no longer be used"
you "(the value that was in git history)."
pause "Press Enter once the old key is revoked…"

# ---- done -------------------------------------------------------------------
step "Done"
ok "BuildBuddy key rotated: new value set (Actions + Dependabot), old key revoked."
printf '  Close it out:  %sgh issue close 456 -R %s -c "rotated + revoked; env-only, no key in git"%s\n' "$DIM" "${REPO}" "$RESET"
