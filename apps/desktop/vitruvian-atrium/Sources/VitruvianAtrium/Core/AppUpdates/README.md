# Appupdates

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Core/AppUpdates`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [AppUpdateFeedSupport.swift:95]: `base.query == nil else { return nil }`
- [AppUpdateFeedSupport.swift:231]: `private let metadataNamespace = "http://www.andymatuschak.org/xml-namespaces/...`
- [AppUpdatesSupport.swift:417]: `var query = [URLQueryItem(name: "bundleId", value: bundleIDs.joined(separator...`
- [AppUpdatesSupport.swift:420]: `query.append(URLQueryItem(name: "country", value: country))`
- [AppUpdatesSupport.swift:422]: `components?.queryItems = query`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Core/AppUpdates/...`
