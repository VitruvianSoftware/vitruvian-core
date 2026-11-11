# Snippets

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Sources/Vitruvian/Services/Snippets`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [SnippetLibraryService.swift:21]: `@Published package var query = "" {`
- [SnippetLibraryService.swift:70]: `TextSnippetSupport.librarySections(snippets, query: query)`
- [SnippetLibraryService.swift:103]: `query = ""`
- [TextSnippetSupport.swift:470]: `/// underscores, but nobody types a timezone query that way.`
- [TextSnippetSupport.swift:475]: `/// How well an identifier answers a query, lowest first, so that a`
- [TextSnippetSupport.swift:479]: `private static func timeZoneMatchRank(_ identifier: String, query: String) ->...`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Sources/Vitruvian/Services/Snippets/...`
