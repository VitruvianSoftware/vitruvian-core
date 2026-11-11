# Catalog

## Overview
Component package providing implementation for `apps/web/backstage/packages/app/src/components/catalog`.

## Interface
- `[CloudRunCard.tsx:CloudRunCard]`
- `[DeployWorkflowRunsCard.tsx:DeployWorkflowRunsCard]`
- `[EntityOpenTelemetryCard.tsx:EntityOpenTelemetryCard]`
- `[EntityPage.tsx:entityPage]`
- `[EntityReleaseCard.tsx:EntityReleaseCard]`
- `[EntityScorecardCard.tsx:EntityScorecardCard]`
- `[EntitySdlcCard.tsx:EntitySdlcCard]`
- `[EntityStorybookCard.tsx:EntityStorybookCard]`
- `[EntityStorybookContent.tsx:EntityStorybookContent]`
- `[OpenTelemetryContent.tsx:OpenTelemetryContent]`
- `[cloudRun.ts:CLOUD_RUN_ANNOTATION]`
- `[cloudRun.ts:readCloudRunRefs]`
- `[cloudRun.ts:isCloudRunAvailable]`
- `[deployWorkflowRuns.ts:DEPLOY_WORKFLOW_ANNOTATION]`
- `[deployWorkflowRuns.ts:RELEASE_WORKFLOW_ANNOTATION]`
- `[deployWorkflowRuns.ts:PROJECT_SLUG_ANNOTATION]`
- `[deployWorkflowRuns.ts:DeployRun]`
- `[deployWorkflowRuns.ts:readDeployWorkflow]`
- `[deployWorkflowRuns.ts:readProjectSlug]`
- `[deployWorkflowRuns.ts:isDeployWorkflowAvailable]`

## Invariants
- None

## Side Effects
- [CloudRunCard.tsx:68]: `const res = await fetchApi.fetch(`
- [DeployWorkflowRunsCard.tsx:82]: `const res = await fetch(runsUrl(slug, workflow, limit), { headers });`
- [DeployWorkflowRunsCard.tsx:87]: `// Fetch each run's jobs so a green-but-entirely-skipped deploy can be`
- [DeployWorkflowRunsCard.tsx:92]: `const jr = await fetch(`
- [EntityOpenTelemetryCard.tsx:69]: `http://opentelemetry-collector.opentelemetry.svc.cluster.local:4318`
- [EntityReleaseCard.tsx:74]: `const res = await fetch(`
- [EntityReleaseCard.tsx:112]: `const res = await fetch(`
- [EntityScorecardCard.tsx:171]: `const res = await fetchApi.fetch(`
- [OpenTelemetryContent.tsx:111]: `"http://opentelemetry-collector.opentelemetry.svc.cluster.local:4318",`
- [OpenTelemetryContent.tsx:112]: `protocol: "OTLP / HTTP & gRPC (4317)",`

## Verification
- Run: `bazel test //apps/web/backstage/packages/app/src/components/catalog/...`
