# Seed

## Overview
Component package providing implementation for `apps/desktop/vitruvian-courier/engine/internal/seed`.

## Interface
- `[seed.go:Marker]`
- `[seed.go:PlayedFile]`
- `[seed.go:Me]`
- `[seed.go:Scenario]`
- `[seed.go:Account]`
- `[seed.go:Person]`
- `[seed.go:Chat]`
- `[seed.go:Message]`
- `[seed.go:Reaction]`
- `[seed.go:Load]`
- `[seed.go:Parse]`
- `[seed.go:Check]`
- `[seed.go:Networks]`
- `[seed.go:Name]`
- `[seed.go:Ordered]`
- `[seed.go:Prepare]`
- `[seed.go:Play]`
- `[seed.go:Played]`
- `[seed.go:MarkPlayed]`

## Invariants
- None

## Side Effects
- [seed.go:356]: `return os.WriteFile(filepath.Join(dataDir, PlayedFile), []byte(body), 0o600)`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-courier/engine/internal/seed/...`
