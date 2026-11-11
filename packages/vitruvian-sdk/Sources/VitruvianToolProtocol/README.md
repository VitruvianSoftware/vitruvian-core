# Vitruviantoolprotocol

## Overview
Component package providing implementation for `packages/vitruvian-sdk/Sources/VitruvianToolProtocol`.

## Interface
- `[JSONRPC.swift:RPCID]`
- `[JSONRPC.swift:RPCErrorObject]`
- `[JSONRPC.swift:RPCErrorCode]`
- `[JSONRPC.swift:RPCMessage]`
- `[JSONValue.swift:JSONValue]`
- `[LineFraming.swift:WireLimits]`
- `[LineFraming.swift:LineFraming]`
- `[LineFraming.swift:LineSplitter]`
- `[Messages.swift:ProtocolVersion]`
- `[Messages.swift:AppService]`
- `[Messages.swift:ProtocolFeature]`
- `[Messages.swift:ToolMethod]`
- `[Messages.swift:RefusalCode]`
- `[Messages.swift:RefusalData]`
- `[Messages.swift:EmptyObject]`
- `[Messages.swift:InitializeParams]`
- `[Messages.swift:InitializeResult]`
- `[Messages.swift:CommandRunParams]`
- `[Messages.swift:PreferencesChangedParams]`
- `[Messages.swift:LanguageChangedParams]`

## Invariants
- None

## Side Effects
- [ToolManifestFile.swift:215]: `public let exec: String`
- [ToolManifestFile.swift:244]: `/// value. `field` is where: `runtime.exec`, `contributes.commands[0].id`.`
- [ToolManifestFile.swift:271]: `/// `runtime.exec` is not a path that stays inside the tool's folder.`

## Verification
- Run: `bazel test //packages/vitruvian-sdk/Sources/VitruvianToolProtocol/...`
