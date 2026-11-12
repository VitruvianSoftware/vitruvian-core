# Pb

## Overview
Component package providing implementation for `apps/desktop/courier/engine/internal/gchat/pb`.

## Interface
- `[helpers.go:Marshal]`
- `[helpers.go:MustMarshal]`
- `[helpers.go:Unmarshal]`
- `[helpers.go:Equal]`
- `[helpers.go:String]`
- `[helpers.go:Int64]`
- `[helpers.go:Int32]`
- `[helpers.go:Uint64]`
- `[helpers.go:Uint32]`
- `[helpers.go:Bool]`
- `[helpers.go:SpaceGroupID]`
- `[helpers.go:DMGroupID]`
- `[helpers.go:PartsToGroupID]`
- `[helpers.go:GroupIDToParts]`
- `[helpers.go:HumanUserID]`
- `[helpers.go:UserMemberID]`

## Invariants
- [helpers.go:17]: `panic(err)`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/courier/engine/internal/gchat/pb/...`
