# Engine

## Overview
Component package providing implementation for `apps/desktop/courier/engine/internal/engine`.

## Interface
- `[engine.go:Spec]`
- `[engine.go:BridgeReport]`
- `[engine.go:LoginHook]`
- `[engine.go:Engine]`
- `[engine.go:Status]`
- `[engine.go:New]`
- `[engine.go:Start]`
- `[engine.go:Expect]`
- `[engine.go:StartNetworks]`
- `[engine.go:Status]`
- `[engine.go:Host]`
- `[engine.go:HostForRoom]`
- `[engine.go:Names]`
- `[engine.go:Stop]`
- `[engine.go:SetLogin]`
- `[engine.go:ModuleVersions]`
- `[engine.go:Bridges]`
- `[engine.go:RestartNetwork]`
- `[engine.go:RemoveAccount]`
- `[engine.go:RefreshSubAccounts]`

## Invariants
- [engine.go:311]: `// startOne builds one network's connector and starts its host. A panic while...`
- [engine.go:313]: `// the other networks still start. Only start-up is covered: a panic later, i...`
- [engine.go:319]: `log.Error().Str("network", spec.Name).Any("panic", r).Bytes("stack", debug.St...`

## Side Effects
- [engine.go:238]: `logins, err := h.Bridge.DB.UserLogin.GetAllForUser(ctx, ids.Me)`
- [engine.go:252]: `// was added) the receiver of their portal, read from the bridge's own databa...`
- [engine.go:258]: `portals, err := h.Bridge.DB.Portal.GetAllWithMXID(ctx)`

## Verification
- Run: `bazel test //apps/desktop/courier/engine/internal/engine/...`
