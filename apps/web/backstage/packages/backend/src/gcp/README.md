# Gcp

## Overview
Component package providing implementation for `apps/web/backstage/packages/backend/src/gcp`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [dashboardSelectors.test.ts:92]: `// Only single-word selectors are tag-matched; anything else is a query.`
- [workloadIdentityWiring.test.ts:175]: `// so defaultProject alone resolves to "" and every query 400s. Grafana would`

## Verification
- Run: `bazel test //apps/web/backstage/packages/backend/src/gcp/...`
