# Localmatrix

## Overview
Component package providing implementation for `apps/desktop/courier/engine/internal/localmatrix`.

## Interface
- `[connector.go:Connector]`
- `[connector.go:New]`
- `[connector.go:Bridge]`
- `[connector.go:Init]`
- `[connector.go:Start]`
- `[connector.go:PreStop]`
- `[connector.go:Stop]`
- `[connector.go:GetCapabilities]`
- `[connector.go:ParseGhostMXID]`
- `[connector.go:FormatGhostMXID]`
- `[connector.go:GhostIntent]`
- `[connector.go:NewUserIntent]`
- `[connector.go:BotIntent]`
- `[connector.go:SendBridgeStatus]`
- `[connector.go:SendMessageStatus]`
- `[connector.go:GenerateContentURI]`
- `[connector.go:ParseContentURI]`
- `[connector.go:GetPowerLevels]`
- `[connector.go:GetMembers]`
- `[connector.go:GetMemberInfo]`

## Invariants
- None

## Side Effects
- [connector.go:199]: `if errors.Is(err, sql.ErrNoRows) {`
- [intent.go:296]: `defer os.Remove(tmp.Name())`
- [intent.go:329]: `defer os.Remove(tmp.Name())`
- [intent.go:338]: `defer os.Remove(res.ReplacementFile)`

## Verification
- Run: `bazel test //apps/desktop/courier/engine/internal/localmatrix/...`
