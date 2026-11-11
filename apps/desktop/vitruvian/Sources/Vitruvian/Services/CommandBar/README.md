# Commandbar

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Sources/Vitruvian/Services/CommandBar`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [CommandBarExtras.swift:99]: `/// reads this instead of asking CoreWLAN on the main thread: the query`
- [CommandBarFileSearch.swift:13]: `/// work, a query is asked of Spotlight once and its answer is thrown away when`
- [CommandBarFileSearch.swift:31]: `/// is faster than this, which is the point: a query per keystroke would`
- [CommandBarFileSearch.swift:35]: `/// Called on the main thread when results for some query become ready.`
- [CommandBarFileSearchSupport.swift:40]: `/// The query in Spotlight's own language, or nil when there is nothing`
- [CommandBarFileSearchSupport.swift:43]: `package static func expression(for query: String) -> String? {`
- [CommandBarFileSearchSupport.swift:44]: `let words = query.split(whereSeparator: \.isWhitespace).map(String.init)`
- [CommandBarLinks.swift:58]: `destination.contains(CommandBarLinkPlaceholder.query.token)`
- [CommandBarLinks.swift:61]: `/// True for anything that reads whatever follows its name: every query`
- [CommandBarLinks.swift:100]: `case query`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Sources/Vitruvian/Services/CommandBar/...`
