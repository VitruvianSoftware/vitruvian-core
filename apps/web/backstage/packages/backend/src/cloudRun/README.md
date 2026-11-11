# Cloudrun

## Overview
Component package providing implementation for `apps/web/backstage/packages/backend/src/cloudRun`.

## Interface
- `[plugin.ts:cloudRunPlugin]`
- `[refs.ts:CloudRunRef]`
- `[refs.ts:CLOUD_RUN_ANNOTATION]`
- `[refs.ts:parseCloudRunRefs]`
- `[refs.ts:serviceUrl]`
- `[refs.ts:CloudRunStatus]`
- `[refs.ts:mapService]`

## Invariants
- None

## Side Effects
- [catalogAnnotations.test.ts:45]: `fs.readFileSync(path.join(REPO, rel), "utf8"),`
- [plugin.ts:50]: `deps: { http: coreServices.httpRouter, logger: coreServices.logger },`
- [plugin.ts:51]: `async init({ http, logger }) {`
- [plugin.ts:62]: `typeof req.query.refs === "string" ? req.query.refs : undefined,`

## Verification
- Run: `bazel test //apps/web/backstage/packages/backend/src/cloudRun/...`
