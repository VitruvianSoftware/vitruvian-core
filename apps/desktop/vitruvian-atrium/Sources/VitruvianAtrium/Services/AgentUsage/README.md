# Agentusage

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/AgentUsage`.

## Interface
- `[AgentLogObject.swift:AgentLogObject]`
- Subdirectory: [Harness](./Harness/README.md)

## Invariants
- None

## Side Effects
- [AgentAntigravityReader.swift:63]: `let query = "SELECT conversation_id, workspace_uris FROM conversation_summaries"`
- [AgentAntigravityReader.swift:66]: `guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {`
- [AgentAntigravityReader.swift:237]: `// Subprocess discovery of language_server`
- [AgentClaudeServer.swift:114]: `/// the account's usage. After a failed fetch, get_usage answers from`
- [AgentOpenCodeReader.swift:38]: `/// them by. The query takes out only these, so prompts, replies, the`
- [AgentOpenCodeReader.swift:384]: `/// A JSON value that reads as null, instead of failing the whole query,`
- [AgentOpenCodeReader.swift:390]: `private static func exists(_ db: OpaquePointer?, _ query: String) -> Bool {`
- [AgentPriceSource.swift:78]: `let session = URLSession(configuration: configuration, delegate: delegate, de...`
- [AgentPriceSource.swift:83]: `func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPR...`
- [AgentPriceSource.swift:89]: `func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didRecei...`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/AgentUsage/...`
