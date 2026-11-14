# Remotetooltests

## Overview
Component package providing implementation for `apps/mobile/vitruvian-remote/macmenu/Tests/RemoteToolTests`.

## Interface
- `[RemoteToolTests.swift:RemoteToolTests]`
- `[SettingsSectionsTests.swift:SettingsSectionsTests]`

## Invariants
- None

## Side Effects
- [RemoteToolTests.swift:116]: `XCTAssertTrue(treeContains(qrTree, "http://100.64.0.12:7411/pair?code="))`

## Verification
- Run: `bazel test //apps/mobile/vitruvian-remote/macmenu/Tests/RemoteToolTests/...`
