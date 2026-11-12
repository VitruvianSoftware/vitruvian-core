# Ids

## Overview
Component package providing implementation for `apps/desktop/courier/engine/internal/ids`.

## Interface
- `[ids.go:ServerName]`
- `[ids.go:Me]`
- `[ids.go:GhostMXID]`
- `[ids.go:ParseGhostMXID]`
- `[ids.go:RoomID]`
- `[ids.go:EventID]`
- `[ids.go:ReactionEventID]`
- `[ids.go:RandomEventID]`
- `[ids.go:ContentURI]`
- `[ids.go:ParseContentURI]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/courier/engine/internal/ids/...`
