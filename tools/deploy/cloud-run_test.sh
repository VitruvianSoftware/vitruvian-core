#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Unit tests for the cloud-run deploy sequencer. Exercises the pure #808
# smoke-URL logic by SOURCING the script, and the phase planning + arg guards
# by running it with --dry-run (no gcloud/pulumi needed). The script under test
# arrives as $1 via $(location) so this works under `bazel test` without runfiles
# glue (same pattern as //tools/pulumi:resolve_identity_test).
set -uo pipefail

SCRIPT="${1:?usage: cloud-run_test.sh <path-to-cloud-run.sh>}"
fails=0
ok() { echo "ok - $1"; }
bad() { echo "NOT OK - $1"; fails=$((fails + 1)); }

# --- pure resolve_smoke_url (#808) -----------------------------------------
# shellcheck source=/dev/null
source "$SCRIPT"   # source-safe: main() runs only when executed, not sourced
# Sourcing imported cloud-run.sh's `set -euo pipefail`; clear the inherited -e so
# the arg-guard cases below (which intentionally exit 2) don't abort this test.
set +e -u -o pipefail

got="$(resolve_smoke_url "https://cand.example" "false" "https://live.example")"
[ "$got" = "https://cand.example" ] && ok "candidate URL wins when present" \
  || bad "candidate URL should win (got '$got')"

got="$(resolve_smoke_url "" "true" "https://live.example")"
[ "$got" = "https://live.example" ] && ok "first deploy falls back to live service URL" \
  || bad "first deploy should use service URL (got '$got')"

if resolve_smoke_url "" "false" "https://live.example" >/dev/null 2>&1; then
  bad "non-first deploy with no candidate MUST fail (#808 false-green guard)"
else
  ok "non-first deploy with unresolvable candidate fails closed (#808)"
fi

got="$(resolve_smoke_url "null" "true" "https://live.example")"
[ "$got" = "https://live.example" ] && ok "literal 'null' candidate treated as unresolved" \
  || bad "'null' candidate should be unresolved (got '$got')"

# --- phase planning via --dry-run ------------------------------------------
common=(--pulumi-dir tabula/infra/app --service tabula-api --env development \
  --env-prefix TABULA --project prj-x --region us-central1 \
  --image-digest 'reg/app@sha256:abc' --dry-run)

# steady-state (--stable-revision seeds an existing revision): --phase all must
# run candidate (PROMOTE=false) then promote (PROMOTE=true), reusing that revision.
out="$(bash "$SCRIPT" "${common[@]}" --stable-revision rev-old --phase all 2>&1)"
echo "$out" | grep -q '\[candidate\] TABULA_PROMOTE=false TABULA_STABLE_REVISION=rev-old' \
  && ok "candidate sets PROMOTE=false with the captured stable" || bad "candidate plan wrong:\n$out"
echo "$out" | grep -q '\[promote\] TABULA_PROMOTE=true TABULA_STABLE_REVISION=rev-old' \
  && ok "promote sets PROMOTE=true reusing the SAME stable" || bad "promote plan wrong:\n$out"
[ "$(echo "$out" | grep -c 'DRYRUN pulumi: .* pulumi up --stack development --yes')" -eq 2 ] \
  && ok "phase=all issues exactly two pulumi up (candidate + promote)" || bad "expected 2 pulumi up:\n$out"
echo "$out" | grep -q 'first_deploy=false' && ok "seeded stable => not a first deploy" || bad "should be non-first:\n$out"

# --refresh scopes to the candidate up ONLY (matches _deploy-cloud-run.yaml:
# candidate `up --refresh`, promote plain `up` -- state is already reconciled).
out="$(bash "$SCRIPT" "${common[@]}" --stable-revision rev-old --phase all --refresh 2>&1)"
echo "$out" | grep -q 'DRYRUN pulumi: .* pulumi up --stack development --yes --refresh' \
  && ok "candidate up refreshes when --refresh is given" || bad "candidate should refresh:\n$out"
[ "$(echo "$out" | grep -c 'pulumi up --stack development --yes --refresh')" -eq 1 ] \
  && ok "ONLY the candidate refreshes; promote never does" || bad "refresh must scope to candidate only:\n$out"

# first-ever deploy: no --stable-revision, dry-run => STABLE empty => first_deploy=true
out="$(bash "$SCRIPT" "${common[@]}" --phase candidate 2>&1)"
echo "$out" | grep -q 'first_deploy=true' && ok "no stable => first deploy" || bad "should be first deploy:\n$out"

# image tag path (no digest)
out="$(bash "$SCRIPT" --pulumi-dir d --service s --env development --env-prefix OUI \
  --project p --region r --image-tag v1 --dry-run --phase candidate 2>&1)"
echo "$out" | grep -q 'OUI_IMAGE_TAG = v1' && ok "--image-tag maps to <PREFIX>_IMAGE_TAG" || bad "image-tag wrong:\n$out"

# --- arg guards ------------------------------------------------------------
bash "$SCRIPT" --service s --env e --env-prefix P --project p --region r --image-tag v --dry-run >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "missing --pulumi-dir exits 2" || bad "missing required arg should exit 2"

bash "$SCRIPT" "${common[@]}" --phase bogus >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "bad --phase exits 2" || bad "bad --phase should exit 2"

bash "$SCRIPT" --pulumi-dir d --service s --env e --env-prefix P --project p --region r --dry-run >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "missing image ref exits 2" || bad "missing --image-* should exit 2"

# --- ensure_stack: self-heals a brand-new environment's missing stack -------
# A NEW environment (no `pulumi stack init` ever run for it) must not need a
# human to pre-provision it before the first deploy can run; deploy_phase's
# `pulumi up --stack "$ENV"` would otherwise fail outright with
# "no stack named '$ENV' found".

# --dry-run: pulumi_wrap's own dry-run branch always reports success, so the
# probe is shown and `stack init` is never reached.
out="$(bash "$SCRIPT" "${common[@]}" --phase candidate --env nonproduction 2>&1)"
echo "$out" | grep -q "DRYRUN pulumi: (dir=tabula/infra/app) ensure stack 'nonproduction' exists" \
  && ok "dry-run shows the ensure_stack probe" || bad "dry-run should probe the stack:\n$out"
echo "$out" | grep -q "pulumi stack init" \
  && bad "dry-run must never reach a real 'pulumi stack init' invocation:\n$out" \
  || ok "dry-run never falls through to a real stack init"

# Real (non-dry-run) branching: stub `pulumi` + the pulumi_cmd.sh wrapper it
# goes through, entirely self-contained (no real gcloud/pulumi/network) --
# same "no real backend needed" bar as the rest of this file.
stack_test_root="$(mktemp -d)"
trap 'rm -rf "$stack_test_root"' EXIT
mkdir -p "$stack_test_root/fakebin" "$stack_test_root/ws/tools/pulumi"
created_stacks="$stack_test_root/created-stacks.txt"
: >"$created_stacks"

cat >"$stack_test_root/fakebin/pulumi" <<FAKEPULUMI
#!/usr/bin/env bash
STATE="$created_stacks"
case "\$1 \$2" in
  "stack select")
    grep -qx "\$3" "\$STATE" && exit 0
    echo "error: no stack named '\$3' found" >&2
    exit 6
    ;;
  "stack init")
    echo "\$3" >>"\$STATE"
    exit 0
    ;;
  *) echo "unexpected fake pulumi invocation: \$*" >&2; exit 99 ;;
esac
FAKEPULUMI
chmod +x "$stack_test_root/fakebin/pulumi"

# Minimal stand-in for tools/pulumi/pulumi_cmd.sh: ensure_stack only relies on
# pulumi_wrap's calling contract (dir as $1, subcommand+args after) -- the real
# wrapper's GCP-identity/backend-pin logic has its own coverage elsewhere.
cat >"$stack_test_root/ws/tools/pulumi/pulumi_cmd.sh" <<'FAKEWRAP'
#!/usr/bin/env bash
set -euo pipefail
shift  # PROJECT_DIR, unused by the stub
SUBCMD="$1"; shift
exec pulumi "$SUBCMD" "$@"
FAKEWRAP

(
  # Reset: `fails` is inherited from the parent shell (a subshell copies
  # variables, not references), so counting from 0 here and reporting it via
  # the exit code is what lets the parent's tally see failures from inside
  # this subshell at all -- a bare `bad` in here would otherwise only ever
  # increment a copy that vanishes when the subshell exits.
  fails=0
  PATH="$stack_test_root/fakebin:$PATH"
  BUILD_WORKSPACE_DIRECTORY="$stack_test_root/ws"
  PULUMI_DIR=tabula/infra/app DRY_RUN= ENV=nonproduction
  export PATH BUILD_WORKSPACE_DIRECTORY PULUMI_DIR DRY_RUN ENV

  ensure_stack
  [ "$(cat "$created_stacks")" = "nonproduction" ] \
    && ok "missing stack gets created on first ensure_stack" \
    || bad "expected 'nonproduction' created, got: $(cat "$created_stacks")"

  before="$(cat "$created_stacks")"
  ensure_stack
  [ "$(cat "$created_stacks")" = "$before" ] \
    && ok "already-existing stack: select succeeds, no spurious re-init" \
    || bad "ensure_stack should be idempotent, state changed to: $(cat "$created_stacks")"

  ENV=production ensure_stack
  [ "$(cat "$created_stacks")" = "$(printf 'nonproduction\nproduction')" ] \
    && ok "a second, still-missing env is created independently" \
    || bad "expected both stacks created, got: $(cat "$created_stacks")"

  exit "$fails"
)
subshell_fails=$?
fails=$((fails + subshell_fails))

echo "---"
if [ "$fails" -eq 0 ]; then echo "PASS (all cloud-run sequencer checks)"; exit 0; fi
echo "FAIL ($fails check(s))"; exit 1
