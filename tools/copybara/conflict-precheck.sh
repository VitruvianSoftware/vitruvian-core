#!/usr/bin/env bash
#
# Conflict pre-check for the vitruvian-core <-> standalone bidirectional sync.
# Generalized across components (mcp-slack, devx, homelab, nexus-agent, ...).
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
# (export stamps MONOREPO_REV_ID; import stamps <COMPONENT>_REV_ID). A synced-in
# change carries the peer label and is ignored here.
#
# Usage: conflict-precheck.sh <export|import> <component> <monorepo_dir> <standalone_dir> [standalone_only...]
#   <component>        the monorepo subfolder / standalone repo name (e.g. devx).
#   <standalone_only>  zero or more repo-relative paths that exist ONLY in the
#                      standalone (the dispatch workflow; npm lockfile for node
#                      components). Excluded from the standalone "genuine change"
#                      scan since they never cross the boundary.
#   Both repos must be checked out with FULL history (the baseline commit must be
#   reachable). If a baseline is missing/unreachable the check no-ops (exit 0) —
#   e.g. a fresh, not-yet-seeded destination.
set -euo pipefail

DIRECTION="${1:?usage: conflict-precheck.sh <export|import> <component> <monorepo_dir> <standalone_dir> [standalone_only...]}"
COMPONENT="${2:?component name (e.g. mcp-slack)}"
MONO="${3:?monorepo dir}"
STD="${4:?standalone dir}"
shift 4
STANDALONE_ONLY=("$@")            # repo-relative paths present ONLY in the standalone

EXPORT_LABEL="MONOREPO_REV_ID"    # export stamps this onto every standalone
# Import label is per-component UPPER_SNAKE + _REV_ID, matching copy.bara.sky:
#   mcp-slack -> MCP_SLACK_REV_ID, devx -> DEVX_REV_ID, nexus-agent -> NEXUS_AGENT_REV_ID
IMPORT_LABEL="$(printf '%s' "$COMPONENT" | tr '[:lower:]-' '[:upper:]_')_REV_ID"

# Monorepo-only Bazel files for this component (gazelle-generated, never synced).
# Both the glob form (nested, e.g. devx/internal/.../BUILD) and the literal
# top-level form, so a pure-BUILD commit is never mistaken for a genuine change.
MONOREPO_ONLY_EXCLUDES=(
  ":(exclude,glob)${COMPONENT}/**/BUILD"
  ":(exclude,glob)${COMPONENT}/**/BUILD.bazel"
  ":(exclude)${COMPONENT}/BUILD"
  ":(exclude)${COMPONENT}/BUILD.bazel"
)

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
    scan=(.)
    for f in ${STANDALONE_ONLY[@]+"${STANDALONE_ONLY[@]}"}; do scan+=(":(exclude)$f"); done
    pending="$(genuine_commits "$STD" "${base}..HEAD" "$EXPORT_LABEL" "${scan[@]}")"
    what="standalone change not yet imported into the monorepo"
    ;;
  import)
    # standalone -> monorepo: fail if the monorepo's <component>/ has a genuine
    # change not yet exported (so the standalone doesn't have it; importing would
    # overwrite it).
    base="$(latest_rev "$STD" "$EXPORT_LABEL")"
    [ -z "$base" ] && { echo "[precheck/import] no export baseline yet — skipping"; exit 0; }
    git -C "$MONO" cat-file -e "${base}^{commit}" 2>/dev/null \
      || { echo "::warning::[precheck/import] export baseline $base not reachable in monorepo — skipping"; exit 0; }
    # syncable monorepo files = <component>/ except the monorepo-only Bazel files
    pending="$(genuine_commits "$MONO" "${base}..HEAD" "$IMPORT_LABEL" \
      "${COMPONENT}/" "${MONOREPO_ONLY_EXCLUDES[@]}")"
    what="monorepo ${COMPONENT}/ change not yet exported to the standalone"
    ;;
  *) echo "unknown direction: $DIRECTION (use export|import)" >&2; exit 2 ;;
esac

if [ -n "$pending" ]; then
  echo "::error title=Copybara conflict pre-check::Refusing to $DIRECTION $COMPONENT — the peer repo has an un-synced $what. Syncing now would overwrite it (concurrent conflicting edit). Reconcile by hand, then re-run."
  echo "Offending un-synced commit(s):"
  echo "$pending"
  exit 1
fi
echo "[precheck/$DIRECTION] OK ($COMPONENT) — no un-synced genuine peer changes (baseline $base)."
