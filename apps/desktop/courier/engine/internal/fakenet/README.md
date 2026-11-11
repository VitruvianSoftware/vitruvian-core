# Fakenet

## Overview
Component package providing implementation for `apps/desktop/courier/engine/internal/fakenet`.

## Interface
- `[fakenet.go:Call]`
- `[fakenet.go:Sent]`
- `[fakenet.go:File]`
- `[fakenet.go:Reaction]`
- `[fakenet.go:Receipt]`
- `[fakenet.go:TagChange]`
- `[fakenet.go:MuteChange]`
- `[fakenet.go:UnreadChange]`
- `[fakenet.go:Accept]`
- `[fakenet.go:Edit]`
- `[fakenet.go:Remove]`
- `[fakenet.go:Poll]`
- `[fakenet.go:Vote]`
- `[fakenet.go:TimerChange]`
- `[fakenet.go:TypingChange]`
- `[fakenet.go:ChatStart]`
- `[fakenet.go:StartChats]`
- `[fakenet.go:Contact]`
- `[fakenet.go:DirectChatID]`
- `[fakenet.go:Chat]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/courier/engine/internal/fakenet/...`
