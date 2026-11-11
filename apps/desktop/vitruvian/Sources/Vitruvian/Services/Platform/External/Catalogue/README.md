# Catalogue

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/External/Catalogue`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [CatalogueClient.swift:189]: `/// True only for a rehearsal: plain http to this Mac itself is allowed.`
- [CatalogueClient.swift:216]: `list.scheme == "http", list.host == "127.0.0.1",`
- [CatalogueClient.swift:224]: `/// Whether the app may fetch `url`: https anywhere, or plain http to`
- [CatalogueInstaller.swift:111]: `parts.fetcher.fetch(`
- [CatalogueInstalls.swift:17]: `/// What a fetch came to, waiting for the page.`
- [CatalogueInstalls.swift:29]: `/// What the last fetch came to, until the page takes it.`
- [CatalogueWatch.swift:14]: `/// none installed it fetches nothing on its own. Each fetch sends the ETag of`
- [CatalogueWatch.swift:23]: `/// A fetch is in flight and there is nothing to show yet.`
- [CatalogueWatch.swift:100]: `/// Fetches the list now, unless a fetch is already in flight.`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/External/Catalogue/...`
