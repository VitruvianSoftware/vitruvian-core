# Host

## Overview
Component package providing implementation for `apps/desktop/courier/engine/internal/host`.

## Interface
- `[host.go:Host]`
- `[host.go:Option]`
- `[host.go:WithConfigure]`
- `[host.go:Start]`
- `[host.go:Stop]`
- `[host.go:Close]`
- `[host.go:Me]`
- `[host.go:DeleteOfflineUserLogin]`

## Invariants
- [host.go:90]: `// Closed again on every way out but success, a panic in the connector includ...`

## Side Effects
- [host.go:95]: `db.Close()`
- [host.go:151]: `// not wait for goroutines still mid-query (portal loops, the backfill queue,...`
- [host.go:152]: `// sql.DB.Close does not wait for connections in use.`

## Verification
- Run: `bazel test //apps/desktop/courier/engine/internal/host/...`
