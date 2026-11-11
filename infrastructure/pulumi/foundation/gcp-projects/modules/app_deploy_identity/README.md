# App Deploy Identity

## Overview
Component package providing implementation for `infrastructure/pulumi/foundation/gcp-projects/modules/app_deploy_identity`.

## Interface
- `[bu_pipeline.go:PipelineArgs]`
- `[bu_pipeline.go:PipelineResult]`
- `[bu_pipeline.go:DeployBUPipeline]`
- `[main.go:Deploy]`
- `[outputs.go:Result]`
- `[preview.go:PreviewArgs]`
- `[preview.go:PreviewResult]`
- `[preview.go:DeployPreview]`
- `[roles.go:CheckProjectRoles]`
- `[roles.go:CheckConditionalRoles]`
- `[roles.go:NeverProjectWide]`
- `[variables.go:Args]`
- `[variables.go:ConditionalRole]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //infrastructure/pulumi/foundation/gcp-projects/modules/app_deploy_identity/...`
