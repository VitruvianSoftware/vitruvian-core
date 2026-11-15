# Remotemenucore

## Overview
Component package providing implementation for `apps/mobile/vitruvian-remote/macmenu/Sources/RemoteMenuCore`.

## Interface
- `[AgentClient.swift:AgentClient]`
- `[AgentStatus.swift:AgentHealth]`
- `[AgentStatus.swift:PhoneLink]`
- `[AgentStatus.swift:AgentState]`
- `[AgentStatus.swift:StatusSnapshot]`
- `[AgentStatus.swift:PairCode]`
- `[AgentStatus.swift:AgentPaths]`
- `[AgentSupervisor.swift:ClaudeHookInspector]`
- `[AgentSupervisor.swift:AgentSupervisor]`
- `[LiveLock.swift:LiveLock]`
- `[LiveLock.swift:FileLock]`
- `[QRPairing.swift:QRPairing]`
- `[RemoteCoexistence.swift:RemoteChoice]`
- `[RemoteCoexistence.swift:RemoteChoiceFile]`
- `[RemoteCoexistence.swift:RemoteRole]`
- `[RemoteCoexistence.swift:RemoteCoexistence]`
- `[RemoteCoexistence.swift:RemoteSideSummary]`
- `[RemoteCoexistence.swift:RemoteDataCopy]`
- `[RemoteProfile.swift:RemoteProfile]`
- `[RemoteSettings.swift:RemoteSettings]`

## Invariants
- None

## Side Effects
- [AgentClient.swift:44]: `let (status, health): (Int?, AgentHealth?) = await fetch("/healthz")`
- [AgentClient.swift:49]: `let (_, p): (Int?, PhoneLink?) = await fetch("/v1/phone")`
- [AgentClient.swift:76]: `guard let url = URL(string: "http://\(address):\(baseURL.port ?? 7411)/health...`
- [AgentStatus.swift:124]: `/// Decide the state from what the probe saw. `status` is the HTTP code, or`
- [AgentStatus.swift:199]: `public static let baseURL = URL(string: "http://127.0.0.1:7411")!`
- [QRPairing.swift:29]: `/// scheme as plain text (Google issue 321657269) but opens any http link. The`
- [QRPairing.swift:36]: `return URL(string: "http://\(address):7411/pair?code=\(code)")`
- [RemoteProfile.swift:216]: `return #"claude mcp add --transport http vitruvian-remote-phone http://127.0....`
- [RemoteSettings.swift:138]: `/// non-empty, and never emits `--exec-dir` unless the directory exists on disk,`
- [RemoteSettings.swift:197]: `args += ["--exec-dir", expanded]`

## Verification
- Run: `bazel test //apps/mobile/vitruvian-remote/macmenu/Sources/RemoteMenuCore/...`
