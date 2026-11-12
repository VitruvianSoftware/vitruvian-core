# Datadir

## Overview
Component package providing implementation for `apps/desktop/courier/engine/internal/datadir`.

## Interface
- `[lock.go:ErrLocked]`
- `[lock.go:LockedError]`
- `[lock.go:Error]`
- `[lock.go:Is]`
- `[lock.go:Lock]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/courier/engine/internal/datadir/...`
