# Utils

## Overview
Component package providing implementation for `infrastructure/pulumi/platform/dev-local/pkg/utils`.

## Interface
- `[config.go:PulumiConfig]`
- `[config.go:NewConfig]`
- `[config.go:GetNamespace]`
- `[config.go:GetString]`
- `[config.go:Lookup]`
- `[config.go:LookupSecret]`
- `[config.go:GetBool]`
- `[config.go:GetInt]`
- `[config.go:RequireSecret]`
- `[random.go:GenerateRandomPassword]`
- `[yaml.go:LoadHelmValues]`
- `[yaml.go:MergeValues]`

## Invariants
- [config.go:104]: `// Use RequireSecret to get the secret value. This will panic if not found.`

## Side Effects
- None

## Verification
- Run: `bazel test //infrastructure/pulumi/platform/dev-local/pkg/utils/...`
