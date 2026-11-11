# Githubtoolcore

## Overview
Component package providing implementation for `apps/desktop/vitruvian-tool-github/Sources/GitHubToolCore`.

## Interface
- `[API.swift:Transport]`
- `[API.swift:APIError]`
- `[API.swift:URLSessionTransport]`
- `[API.swift:GitHubAPI]`
- `[Auth.swift:AccessToken]`
- `[Auth.swift:Paths]`
- `[Auth.swift:CLIAccount]`
- `[Auth.swift:DeviceCode]`
- `[Auth.swift:DevicePollResult]`
- `[Auth.swift:DeviceFlowFailure]`
- `[Auth.swift:DeviceFlowWaiting]`
- `[Auth.swift:DeviceFlowInput]`
- `[Auth.swift:DeviceFlowState]`
- `[Auth.swift:AuthFailure]`
- `[Auth.swift:AuthState]`
- `[GitHubTool.swift:ToolHost]`
- `[GitHubTool.swift:IslandStatus]`
- `[GitHubTool.swift:GitHubTool]`
- `[Models.swift:RepoKey]`
- `[Models.swift:GitHubIdentity]`

## Invariants
- None

## Side Effects
- [API.swift:6]: `/// One HTTP exchange, answered before it returns. The tool sends through`
- [API.swift:7]: `/// `URLSession`; tests answer themselves, so no test reaches the network.`
- [API.swift:16]: `/// An answer that was not HTTP, or not the JSON asked for.`
- [Auth.swift:202]: `/// GitHub answered with an HTTP error other than 401.`
- [Words.swift:430]: `"en": "GitHub refused the request (HTTP %@).",`
- [Words.swift:431]: `"pt-BR": "O GitHub recusou o pedido (HTTP %@).",`
- [Words.swift:432]: `"tr": "GitHub isteği reddetti (HTTP %@).",`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-tool-github/Sources/GitHubToolCore/...`
