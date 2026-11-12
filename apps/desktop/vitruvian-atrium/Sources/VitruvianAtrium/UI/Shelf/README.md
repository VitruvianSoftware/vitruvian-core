# Shelf

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Sources/Vitruvian/UI/Shelf`.

## Interface
- Internal implementation components

## Invariants
- [ShelfTilesView.swift:207]: `// Revealing does not require rebuilding any tile, so keep the`
- [ShelfTilesView.swift:281]: `// precondition, rather than recording the serial ahead of a check`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Sources/Vitruvian/UI/Shelf/...`
