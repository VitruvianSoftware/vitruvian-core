# Update

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Sources/Vitruvian/Core/Update`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [VitruvianReleases.swift:172]: `/// One HTTP reply, with the parts the check reads.`
- [VitruvianReleases.swift:191]: `let (data, response) = try await URLSession.shared.data(for: request)`
- [VitruvianReleases.swift:192]: `guard let http = response as? HTTPURLResponse else { throw URLError(.badServe...`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Sources/Vitruvian/Core/Update/...`
