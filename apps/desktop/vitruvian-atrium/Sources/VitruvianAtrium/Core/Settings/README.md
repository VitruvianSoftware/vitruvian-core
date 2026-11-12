# Settings

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Core/Settings`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [ExtensionsPageSupport.swift:56]: `/// opens once the page is free, as a catalog fetch's result does.`
- [SettingsSearchSupport.swift:231]: `/// "Metrics", "moni" finds "Monitor". A blank query matches everything.`
- [SettingsSearchSupport.swift:234]: `package static func matches(query: String, title: String, keywords: [String] ...`
- [SettingsSearchSupport.swift:235]: `let foldedQuery = fold(query)`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Core/Settings/...`
