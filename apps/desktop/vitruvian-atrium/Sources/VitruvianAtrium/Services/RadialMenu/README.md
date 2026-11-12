# Radialmenu

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Sources/Vitruvian/Services/RadialMenu`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [RadialNowPlayingService.swift:33]: `bridge.fetch { [weak self] snapshot in`
- [RadialNowPlayingService.swift:410]: `func fetch(completion: @escaping (RadialNowPlayingSnapshot?) -> Void) {`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Sources/Vitruvian/Services/RadialMenu/...`
