# Plan: Delivery Orchestrator — Phases 2 + 3 (full migration, then legacy deletion)

> Spec: `docs/superpowers/specs/2026-08-19-delivery-orchestrator-design.md`.
> Goal (James, 2026-08-20): drive all remaining phases to completion to enable
> the keep-vs-rollback decision. Method unchanged: parity-vs-legacy tests,
> mutation verification, live A/B per migration before any legacy deletion.

## Phase 2 — migrate every push-lane + promotion unit

Wave B1 (generator core + tabula + oauth completion):
1. Generator: SHARED BUILD jobs (`shared_build` attr; tabula's one build → two
   digest outputs consumed by tabula-api and tabula-web), RELEASE-PROMOTION
   rungs (tag-prefix conditions per unit, `require-dev-soak.sh` interlock
   transcribed, nonprod→prod chains, companions per rung for oauth's
   zitadel-nonprod/prod), TRANSCRIBED-STEPS render mode (parity-tested verbatim
   step transcription for units with no reusable workflow), WORKFLOW_DISPATCH
   inputs (unit + environment + allow-unsoaked) — required before Phase 3 can
   delete the legacy dispatch escape hatches — and a generated `changelog` job
   (calls `_changelog-summary.yaml`, keyed on any-affected; closes the deferred
   Phase-1 flag).
2. Declarations: tabula-api, tabula-web (promotion tags tabula-api-v /
   tabula-web-v, soak DEV_JOB_NAMEs `<unit>-development / deploy`); oauth
   promotion attrs.
3. Legacy surgery: tabula-deploy.yaml and oauth-user-inspector-deploy.yaml lose
   push AND release triggers (dispatch-only shells pending Phase 3 deletion).

Wave B2 (remaining units, transcribed/reusable):
4. tabula-dev-latest (publish), charts-publish (publish, chart paths),
   tabula-identity-stack + oauth-user-inspector-identity-stack (pulumi ladders,
   ALL rungs on push, gh-environment pattern `foundation-proj-{env}`),
   tabula-build-stack (pulumi, single rung, env foundation-proj-shared),
   copybara-sync-auth-apply (pulumi, narrow paths). Trigger removal each.

## Permanent allowlist rows (the Phase 3 hard floor)
Reusables (`_*.yaml`, called by generated), foundation-* (spec non-goal),
_repo-config-apply (governance, spec-excluded), dispatch-only manual ops
(tabula-data-stack, zitadel-apps-mcp-slack-apply), tabula-release.yml
(release-please machinery).

## Phase 3
5. Preflight digest detection: `preflight` attr honored by the orchestrator
   (generalize tabula-deploy-preflight.sh; veto affected=true when live state
   already matches; fail-open on any preflight error).
6. Delete migrated legacy workflow FILES; tsv shrinks to the hard floor;
   conformance keeps it frozen.
7. Live verification matrix + the rollback-decision report (keep vs level-1/2).

## Verification gates per wave
Parity + mutation tests green · gen idempotent · actionlint · conformance ·
live run per migrated class before its legacy trigger/file is removed.
