# Homebrew

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Core/Homebrew`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [HomebrewSupport.swift:399]: `package static let installerCommand = #"/bin/bash -c "$(curl -fsSL https://ra...`
- [HomebrewSupport.swift:435]: `package static func search(brewPath: String, kind: HomebrewPackageKind, query...`
- [HomebrewSupport.swift:437]: `return HomebrewCommand(executable: brewPath, arguments: ["search", flag, query])`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Core/Homebrew/...`
