# Courier Engine

## Overview
Component package providing implementation for `apps/desktop/courier/engine/cmd/courier-engine`.

## Interface
- `[main.go:Close]`
- `[mcpstdio.go:RoundTrip]`

## Invariants
- None

## Side Effects
- [main.go:32]: `"os/exec"`
- [main.go:121]: `fs.SetOutput(io.Discard)`
- [main.go:122]: `data := fs.String("data", "", "data directory")`
- [mcpstdio.go:12]: `"net/http"`
- [mcpstdio.go:35]: `// forwarding every request to the running Courier's local API at http://127....`
- [mcpstdio.go:42]: `fs.SetOutput(io.Discard)`
- [seed_on.go:83]: `logins, err := h.Bridge.DB.UserLogin.GetAllForUser(ctx, ids.Me)`

## Verification
- Run: `bazel test //apps/desktop/courier/engine/cmd/courier-engine/...`
