# Peripheralstests

## Overview
Component package providing implementation for `packages/peripherals/Tests/PeripheralsTests`.

## Interface
- `[CLITests.swift:CLIParseTests]`
- `[CLITests.swift:CLIRunnerTests]`
- `[CompXHIDTests.swift:CompXHIDTests]`
- `[CompXProtocolTests.swift:CompXProtocolTests]`
- `[MCPServerTests.swift:MCPServerTests]`
- `[MockTransport.swift:MockTransport]`
- `[MockTransport.swift:Fixtures]`
- `[StatusSignalsTests.swift:StatusSignalsTests]`

## Invariants
- [CLITests.swift:71]: `assertUsageError("signal", "panic")`
- [CLITests.swift:120]: `XCTAssertEqual(runner([]).main(["signal", "panic"]), 2)`
- [MCPServerTests.swift:146]: `let panic = try call(server, "mouse_signal", ["signal": "panic"])`
- [MCPServerTests.swift:147]: `XCTAssertTrue(panic.isError)`
- [MockTransport.swift:25]: `/// write, so tests assert the exact bytes and call order.`

## Side Effects
- None

## Verification
- Run: `bazel test //packages/peripherals/Tests/PeripheralsTests/...`
