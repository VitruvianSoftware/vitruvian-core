# Homebrew

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Sources/Vitruvian/Services/Homebrew`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [HomebrewEnvironment.swift:23]: `/// brew's own list: the lowercase proxy names curl and git read, the`
- [HomebrewEnvironment.swift:75]: `/// exits or an `exec` into another shell, ends the interactive run before`
- [HomebrewManager.swift:52]: `private lazy var analyticsSession: URLSession = {`
- [HomebrewManager.swift:56]: `return URLSession(configuration: configuration)`
- [HomebrewManager.swift:147]: `package func search(query: String, kind: HomebrewPackageKind) {`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Sources/Vitruvian/Services/Homebrew/...`
