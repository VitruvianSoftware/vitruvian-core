# Githubtoolcoretests

## Overview
Component package providing implementation for `apps/desktop/vitruvian-tool-github/Tests/GitHubToolCoreTests`.

## Interface
- `[APITests.swift:FakeTransport]`
- `[APITests.swift:APITests]`
- `[AuthTests.swift:AuthTests]`
- `[GitHubToolTests.swift:FakeHost]`
- `[GitHubToolTests.swift:GitHubToolTests]`
- `[MouseTests.swift:MouseTests]`
- `[MouseTests.swift:ToolFiles]`
- `[PagesTests.swift:PagesTests]`
- `[ParityTests.swift:ParityTests]`
- `[VerdictTests.swift:VerdictTests]`
- `[WatchlistAndSecretsTests.swift:WatchlistTests]`
- `[WatchlistAndSecretsTests.swift:SecretStoreTests]`
- `[WordsTests.swift:WordsTests]`

## Invariants
- None

## Side Effects
- [APITests.swift:19]: `let path = request.url!.path + (request.url!.query.map { "?" + $0 } ?? "")`
- [APITests.swift:70]: `$0.url?.path == "/repos/acme/web/commits/p7/check-runs" && $0.url?.query == "...`
- [APITests.swift:84]: `XCTAssertTrue(graphqlBody.contains(#""branch":"trunk""#), "GraphQL mergeQueue...`
- [PagesTests.swift:274]: `XCTAssertEqual(failed.english(1), "GitHub refused the request (HTTP 403).")`
- [ParityTests.swift:444]: `XCTAssertTrue(body.contains(field), "the query asks for \(field)")`
- [ParityTests.swift:452]: `XCTAssertEqual(transport.requests.filter { $0.url?.path == "/graphql" }.count...`
- [ParityTests.swift:454]: `// GitHub refusing the query leaves the queue unknown, not empty.`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-tool-github/Tests/GitHubToolCoreTests/...`
