# Scaffolder

## Overview
Component package providing implementation for `apps/web/backstage/packages/backend/src/scaffolder`.

## Interface
- `[appRender.ts:APP_RENDER_ACTION_ID]`
- `[appRender.ts:REQUIRED_ASPECT_VINTAGE]`
- `[appRender.ts:INITIALIZER_CONFIG_REL]`
- `[appRender.ts:INITIALIZER_TASKS_REL]`
- `[appRender.ts:MODULE_ASPECT_REL]`
- `[appRender.ts:ROOT_CATALOG_REL]`
- `[appRender.ts:CATALOG_LOCATION_NAME]`
- `[appRender.ts:STAGE_DIR]`
- `[appRender.ts:APP_NAME_PATTERN]`
- `[appRender.ts:AppRenderInput]`
- `[appRender.ts:AppRenderResult]`
- `[appRender.ts:ShellRunner]`
- `[appRender.ts:RenderApplicationOptions]`
- `[appRender.ts:normaliseTargetPath]`
- `[appRender.ts:assertValidAppName]`
- `[appRender.ts:assertPathMatchesName]`
- `[appRender.ts:registersRenderApp]`
- `[appRender.ts:assertStampingTarget]`
- `[appRender.ts:resolveContainedOutput]`
- `[appRender.ts:findAspectBinary]`

## Invariants
- [appRender.test.ts:249]: `// The empty string falls back to the default, so assert on the shape`
- [appRender.ts:258]: `* Assert the workspace is a repository this action can stamp into, naming the`

## Side Effects
- [appRender.test.ts:182]: `// the injected `exec` — which is correct behaviour, and it meant this suite`
- [appRender.test.ts:187]: `// hermetic; the binary is never executed, because `exec` is always injected.`
- [appRender.test.ts:206]: `// The default `exec` is the (mocked) package export; give it the same`
- [appRender.ts:31]: `writeFile,`
- [appRender.ts:155]: `exec?: ShellRunner;`
- [appRender.ts:312]: `* subprocess. With `lstat` the broken link counts as existing, `realpath` then`
- [appRenderE2e.test.ts:30]: `*     ASPECT_E2E=1 pnpm exec jest src/scaffolder/appRenderE2e`
- [stampApplicationTemplate.test.ts:62]: `*   fetch:plain                  — @backstage/plugin-scaffolder-backend@4.0.2,`
- [stampApplicationTemplate.test.ts:63]: `*                                  dist/scaffolder/actions/builtin/fetch/plai...`
- [stampApplicationTemplate.test.ts:68]: `"fetch:plain": '@backstage/plugin-scaffolder-backend"',`

## Verification
- Run: `bazel test //apps/web/backstage/packages/backend/src/scaffolder/...`
