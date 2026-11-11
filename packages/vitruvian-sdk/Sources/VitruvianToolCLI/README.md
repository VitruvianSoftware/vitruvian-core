# Vitruviantoolcli

## Overview
Component package providing implementation for `packages/vitruvian-sdk/Sources/VitruvianToolCLI`.

## Interface
- `[Command.swift:VitruvianToolCommand]`
- `[Desk.swift:Desk]`
- `[FolderCheck.swift:FolderLimits]`
- `[FolderCheck.swift:FolderProblem]`
- `[FolderCheck.swift:FolderReport]`
- `[FolderCheck.swift:FolderCheck]`
- `[NewTool.swift:ToolTemplate]`
- `[NewTool.swift:NewTool]`
- `[NewTool.swift:NewToolProblem]`
- `[NewTool.swift:NewToolWriter]`
- `[Session.swift:RunOptions]`
- `[Session.swift:ToolFamily]`
- `[Session.swift:Session]`
- `[Templates.swift:Templates]`
- `[Templates.swift:Refused]`
- `[Words.swift:Words]`

## Invariants
- [NewTool.swift:258]: `require \(goKit) {{version}}`

## Side Effects
- [Command.swift:167]: `say("ok       program: \(manifest.runtime.exec)")`
- [FolderCheck.swift:111]: `if let manifest, ManifestRules.staysInsideFolder(manifest.runtime.exec) {`
- [FolderCheck.swift:112]: `let program = manifest.runtime.exec`
- [Session.swift:164]: `process.executableURL = folder.appendingPathComponent(manifest.runtime.exec)`
- [Session.swift:172]: `notOK("macOS would not start `\(manifest.runtime.exec)`: \(error.localizedDes...`
- [Session.swift:194]: `line("started", "\(manifest.runtime.exec), in \(dataFolder.path)")`
- [Templates.swift:57]: `"runtime": { "kind": "external", "exec": "bin/tool.py" }`
- [Templates.swift:246]: `"runtime": { "kind": "external", "exec": "bin/tool.py" }`
- [Templates.swift:356]: `"runtime": { "kind": "external", "exec": "bin/tool" }`
- [Words.swift:130]: `let fetch = tool.sdk == nil ? "The first build fetches \(published).\n" : ""`

## Verification
- Run: `bazel test //packages/vitruvian-sdk/Sources/VitruvianToolCLI/...`
