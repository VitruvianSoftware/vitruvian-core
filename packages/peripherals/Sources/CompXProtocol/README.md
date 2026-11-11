# Compxprotocol

## Overview
Component package providing implementation for `packages/peripherals/Sources/CompXProtocol`.

## Interface
- `[CompXDevice.swift:CompXDevice]`
- `[CompXDevice.swift:Command]`
- `[CompXDevice.swift:FlashAddress]`
- `[CompXDevice.swift:CompXError]`
- `[Frame.swift:Frame]`
- `[Frame.swift:Checksum]`
- `[Lighting.swift:LightingMode]`
- `[Lighting.swift:RGB]`
- `[Lighting.swift:Level]`
- `[Lighting.swift:LightingConfig]`
- `[Messages.swift:Requests]`
- `[Messages.swift:Responses]`

## Invariants
- [Frame.swift:36]: `precondition(data.count <= Frame.maxDataLength, "a frame carries at most 10 d...`
- [Messages.swift:26]: `precondition(nonce.count == 4, "the handshake nonce is 4 bytes")`

## Side Effects
- None

## Verification
- Run: `bazel test //packages/peripherals/Sources/CompXProtocol/...`
