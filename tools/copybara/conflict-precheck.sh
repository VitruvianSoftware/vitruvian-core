#!/usr/bin/env bash
#
# Conflict pre-check for the vitruvian-core <-> mcp-slack bidirectional sync.
#
# The sync (Copybara state-sync) does NOT fail loud on a true conflict: if the
# same content is edited on BOTH repos within one sync cycle, each direction
# overwrites the other and they silently diverge. This pre-check closes that gap
# by REFUSING to sync (exit 1, red CI) when the *peer* repo already has a genuine
# (not synced-in) change that has not been reflected back yet — because syncing
# now would overwrite it. Run on BOTH directions, a conflict fails both runs
# loudly and neither overwrites, leaving both edits intact for manual reconcile.
#
# "Genuine" = a commit that does NOT carry the *other* direction's rev-id label
# (export stamps MONOREPO_REV_ID; import stamps MCP_SLACK_REV_ID). A synced-in
# change carries the peer label and is ignored here.
#
# Usage: conflict-precheck.sh <export|import> <monorepo_dir> <standalone_dir>
#   Both repos must be checked out with FULL history (the baseline commit must be
#   reachable). If a baseline is missing/unreachable the check no-ops (exit 0) —
#   e.g. a fresh, not-yet-seeded destination.
set -euo pipefail

DIRECTION="${1:?usage: conflict-precheck.sh <export|import> <monorepo_dir> <standalone_dir>}"
MONO="${2:?monorepo dir}"
STD="${3:?standalone dir}"

EXPORT_LABEL="MONOREPO_REV_ID"    # export stamps this onto the standalone
IMPORT_LABEL="MCP_SLACK_REV_ID"   # import stamps this onto the monorepo

# Most recent value of <label> in <repo>'s current-branch history (= the rev the
# peer direction last recorded). Empty if none.
latest_rev() { # <repo_dir> <label>
  git -C "$1" log -1 --grep="$2:" --format=%B 2>/dev/null \
    | sed -n "s/^$2: \\([0-9a-f]\\{7,40\\}\\).*/\\1/p" | head -1
}

# Genuine (peer-label-absent) commits in <repo> over <range>, limited to the
# given pathspecs. "Genuine" = message does NOT contain <peer_label>.
genuine_commits() { # <repo_dir> <range> <peer_label> <pathspec...>
  local repo="$1" range="$2" label="$3"; shift 3
  git -C "$repo" log "$range" --no-merges --invert-grep --grep="$label:" \
    --format='  %h %s' -- "$@" 2>/dev/null
}

case "$DIRECTION" in
  export)
    # monorepo -> standalone: fail if the standalone has a genuine change not yet
    # imported (so the monorepo doesn't have it, and exporting would overwrite it).
    base="$(latest_rev "$MONO" "$IMPORT_LABEL")"
    [ -z "$base" ] && { echo "[precheck/export] no import baseline yet — skipping"; exit 0; }
    git -C "$STD" cat-file -e "${base}^{commit}" 2>/dev/null \
      || { echo "::warning::[precheck/export] import baseline $base not reachable in standalone — skipping"; exit 0; }
    # syncable standalone files = everything except the standalone-only context files
    pending="$(genuine_commits "$STD" "${base}..HEAD" "$EXPORT_LABEL" \
      . ':(exclude)package-lock.json' ':(exclude).github/workflows/sync-to-monorepo.yaml')"
    what="standalone change not yet imported into the monorepo"
    ;;
  import)
    # standalone -> monorepo: fail if the monorepo's mcp-slack/ has a genuine
    # change not yet exported (so the standalone doesn't have it; importing would
    # overwrite it).
    base="$(latest_rev "$STD" "$EXPORT_LABEL")"
    [ -z "$base" ] && { echo "[precheck/import] no export baseline yet — skipping"; exit 0; }
    git -C "$MONO" cat-file -e "${base}^{commit}" 2>/dev/null \
      || { echo "::warning::[precheck/import] export baseline $base not reachable in monorepo — skipping"; exit 0; }
    # syncable monorepo files = mcp-slack/ except the monorepo-only Bazel BUILD
    pending="$(genuine_commits "$MONO" "${base}..HEAD" "$IMPORT_LABEL" \
      mcp-slack/ ':(exclude)mcp-slack/BUILD')"
    what="monorepo mcp-slack/ change not yet exported to the standalone"
    ;;
  *) echo "unknown direction: $DIRECTION (use export|import)" >&2; exit 2 ;;
esac

if [ -n "$pending" ]; then
  echo "::error title=Copybara conflict pre-check::Refusing to $DIRECTION — the peer repo has an un-synced $what. Syncing now would overwrite it (concurrent conflicting edit). Reconcile by hand, then re-run."
  echo "Offending un-synced commit(s):"
  echo "$pending"
  exit 1
fi
echo "[precheck/$DIRECTION] OK — no un-synced genuine peer changes (baseline $base)."
