# External

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/External`.

## Interface
- Internal implementation components
- Subdirectory: [Catalogue](./Catalogue/README.md)

## Invariants
- None

## Side Effects
- [ExternalToolStore.swift:172]: `/// waiting. At once, unless a feature of the app's must first fetch`
- [ExternalToolStore.swift:499]: `/// returns; it may be much later when `Parts.beforeAdding` has to fetch`
- [ProcessTransport.swift:13]: `/// How it is started is `Foundation.Process` and nothing else: no spawn`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/External/...`
