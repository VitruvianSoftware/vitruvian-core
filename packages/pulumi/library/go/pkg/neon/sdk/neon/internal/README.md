# Internal

## Overview
Component package providing implementation for `packages/pulumi/library/go/pkg/neon/sdk/neon/internal`.

## Interface
- `[pulumiUtilities.go:ParseEnvBool]`
- `[pulumiUtilities.go:ParseEnvInt]`
- `[pulumiUtilities.go:ParseEnvFloat]`
- `[pulumiUtilities.go:ParseEnvStringArray]`
- `[pulumiUtilities.go:GetEnvOrDefault]`
- `[pulumiUtilities.go:PkgVersion]`
- `[pulumiUtilities.go:IsZero]`
- `[pulumiUtilities.go:CallPlain]`
- `[pulumiUtilities.go:PkgGetPackageRef]`
- `[pulumiUtilities.go:PkgResourceDefaultOpts]`
- `[pulumiUtilities.go:PkgInvokeDefaultOpts]`
- `[pulumiVersion.go:SdkVersion]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //packages/pulumi/library/go/pkg/neon/sdk/neon/internal/...`
