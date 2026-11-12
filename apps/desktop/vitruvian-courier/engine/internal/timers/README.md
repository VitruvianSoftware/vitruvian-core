# Timers

## Overview
Component package providing implementation for `apps/desktop/courier/engine/internal/timers`.

## Interface
- `[timers.go:MaxSleep]`
- `[timers.go:SweepEvery]`
- `[timers.go:Clock]`
- `[timers.go:RealClock]`
- `[timers.go:Now]`
- `[timers.go:After]`
- `[timers.go:Dispatcher]`
- `[timers.go:Timers]`
- `[timers.go:New]`
- `[timers.go:SetDispatcher]`
- `[timers.go:Poke]`
- `[timers.go:Run]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/courier/engine/internal/timers/...`
