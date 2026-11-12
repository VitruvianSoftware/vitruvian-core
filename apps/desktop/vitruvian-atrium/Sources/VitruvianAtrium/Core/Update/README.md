# Update

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Core/Update`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [VitruvianAtriumReleases.swift:172]: `/// One HTTP reply, with the parts the check reads.`
- [VitruvianAtriumReleases.swift:191]: `let (data, response) = try await URLSession.shared.data(for: request)`
- [VitruvianAtriumReleases.swift:192]: `guard let http = response as? HTTPURLResponse else { throw URLError(.badServe...`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Core/Update/...`
