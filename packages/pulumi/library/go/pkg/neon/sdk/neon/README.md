# Neon

## Overview
Component package providing implementation for `packages/pulumi/library/go/pkg/neon/sdk/neon`.

## Interface
- `[apiKey.go:ApiKey]`
- `[apiKey.go:NewApiKey]`
- `[apiKey.go:GetApiKey]`
- `[apiKey.go:ApiKeyState]`
- `[apiKey.go:ElementType]`
- `[apiKey.go:ApiKeyArgs]`
- `[apiKey.go:ElementType]`
- `[apiKey.go:ApiKeyInput]`
- `[apiKey.go:ElementType]`
- `[apiKey.go:ToApiKeyOutput]`
- `[apiKey.go:ToApiKeyOutputWithContext]`
- `[apiKey.go:ApiKeyOutput]`
- `[apiKey.go:ElementType]`
- `[apiKey.go:ToApiKeyOutput]`
- `[apiKey.go:ToApiKeyOutputWithContext]`
- `[apiKey.go:Key]`
- `[apiKey.go:Name]`
- `[branch.go:Branch]`
- `[branch.go:NewBranch]`
- `[branch.go:GetBranch]`
- Subdirectory: [config](./config/README.md)
- Subdirectory: [internal](./internal/README.md)

## Invariants
- [project.go:96]: `// Storing passwords facilitates access to Neon features that require authori...`
- [project.go:223]: `// Storing passwords facilitates access to Neon features that require authori...`
- [project.go:307]: `// Storing passwords facilitates access to Neon features that require authori...`

## Side Effects
- None

## Verification
- Run: `bazel test //packages/pulumi/library/go/pkg/neon/sdk/neon/...`
