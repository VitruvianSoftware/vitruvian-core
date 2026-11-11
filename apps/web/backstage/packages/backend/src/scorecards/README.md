# Scorecards

## Overview
Component package providing implementation for `apps/web/backstage/packages/backend/src/scorecards`.

## Interface
- `[evaluator.ts:evaluateEntityScorecard]`
- `[factCollectors.ts:determineArchetype]`
- `[factCollectors.ts:collectRunbookFacts]`
- `[factCollectors.ts:collectUptimeFacts]`
- `[factCollectors.ts:collectCiQualityFacts]`
- `[factCollectors.ts:collectSecurityFacts]`
- `[factCollectors.ts:collectRuntimeFacts]`
- `[plugin.ts:scorecardsPlugin]`
- `[router.ts:RouterOptions]`
- `[router.ts:createScorecardRouter]`
- `[types.ts:ComponentArchetype]`
- `[types.ts:ScorecardTrackId]`
- `[types.ts:ScorecardTier]`
- `[types.ts:CheckStatus]`
- `[types.ts:ScorecardCheck]`
- `[types.ts:TrackEvaluation]`
- `[types.ts:LiveDiagnostics]`
- `[types.ts:EvaluatedScorecard]`

## Invariants
- [evaluator.ts:208]: `message: `${archetype.toUpperCase()} components do not require live uptime mo...`
- [evaluator.ts:217]: `message: `${archetype.toUpperCase()} components do not require production on-...`

## Side Effects
- [factCollectors.ts:98]: `const content = await fs.readFile(runbookFullPath, "utf8");`
- [factCollectors.ts:152]: `const res = await fetch(uptimeLink.url, {`
- [factCollectors.ts:222]: `const res = await fetch(url, {`
- [plugin.ts:36]: `http: coreServices.httpRouter,`
- [plugin.ts:42]: `async init({ http, logger, config, discovery, auth }) {`
- [plugin.ts:51]: `http.use(router);`

## Verification
- Run: `bazel test //apps/web/backstage/packages/backend/src/scorecards/...`
