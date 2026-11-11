# Gravastarcli

## Overview
Component package providing implementation for `packages/peripherals/Sources/GravaStarCLI`.

## Interface
- `[CLI.swift:CLICommand]`
- `[CLI.swift:Invocation]`
- `[CLI.swift:UsageError]`
- `[CLI.swift:CLI]`
- `[CLIRunner.swift:CLIRunner]`
- `[MCPServer.swift:MCPServer]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //packages/peripherals/Sources/GravaStarCLI/...`
