# Login

## Overview
Component package providing implementation for `apps/desktop/vitruvian-courier/engine/internal/login`.

## Interface
- `[cookies.go:MaybeURLDecodeCookie]`
- `[cookies.go:CheckCookie]`
- `[fields.go:IsSecret]`
- `[fields.go:CheckField]`
- `[login.go:DefaultIdleTimeout]`
- `[login.go:Driver]`
- `[login.go:NewDriver]`
- `[login.go:Unwrap]`
- `[login.go:StartOptions]`
- `[login.go:Start]`
- `[login.go:StartProcess]`
- `[login.go:Wait]`
- `[login.go:Submit]`
- `[login.go:Cancel]`
- `[login.go:CancelNetwork]`
- `[login.go:SetHost]`
- `[steps.go:Step]`
- `[steps.go:Display]`
- `[steps.go:Field]`
- `[steps.go:CookieStep]`

## Invariants
- None

## Side Effects
- [cookies.go:18]: `// (bridgev2/commands/login.go) and connectors expect the decoded form. Path,...`
- [steps.go:141]: `// unsupported is the answer for a step Vitruvian Courier can't do (a passkey, a raw HT...`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-courier/engine/internal/login/...`
