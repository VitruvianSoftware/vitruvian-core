# Storetest

## Overview
Component package providing implementation for `apps/desktop/vitruvian-courier/engine/internal/store/storetest`.

## Interface
- `[seed.go:SeedEventID]`
- `[seed.go:SeedWord]`
- `[seed.go:SeedTS]`
- `[seed.go:SeedUnindexed]`
- `[seed.go:Indexed]`

## Invariants
- [seed.go:14]: `"github.com/stretchr/testify/require"`
- [seed.go:43]: `require.NoError(t, err)`
- [seed.go:61]: `require.NoError(t, err)`

## Side Effects
- [seed.go:44]: `defer db.Close()`
- [seed.go:60]: `_, err = db.Exec(ctx, q)`
- [seed.go:70]: `defer db.Close()`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-courier/engine/internal/store/storetest/...`
