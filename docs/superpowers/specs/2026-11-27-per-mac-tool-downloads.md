---
status: in-progress
---

# Per-Mac tool downloads

## Why

A tool's folder may hold 256 MB (Atrium's `ToolLimits.folderBytes`, mirrored in
`catalog/src/rules.rs` and `catalog/catalog.schema.json`). The Vitruvian Code
tool folder holds one Node for both Mac architectures. After Node 26 it is
248.7 MiB, so about 7 MiB of room is left, and Node is ~240 of it. The next
Node bump can push it over.

A folder for one architecture holds one thin Node and is about half the size.
It also halves what each user downloads.

## Shape

A catalog entry keeps `download` (for every Mac, required, unchanged) and may
add `downloads`, keyed by architecture:

```json
"download":  { "url": "…/vitruvian-code-tool-1.52.0.zip",        "sha256": "…", "size": 260000000 },
"downloads": {
  "arm64":  { "url": "…/vitruvian-code-tool-1.52.0-arm64.zip",  "sha256": "…", "size": 130000000 },
  "x86_64": { "url": "…/vitruvian-code-tool-1.52.0-x86_64.zip", "sha256": "…", "size": 135000000 }
}
```

- Each value has exactly the shape and rules of `download`: the same URL
  prefixes, sha256 format, and 1..256 MB size.
- `downloads` is optional. When present it has one or both keys; no other keys.
- **Old Atrium** ignores unknown keys (plain `JSONDecoder`), so it keeps
  installing `download`. That is the backward-compatible path.
- **New Atrium** installs `downloads[<the architecture it runs as>]` when that
  key is present, and `download` otherwise. "Runs as" is the compile-time slice
  (`#if arch(arm64)`), the same way Atrium already decides elsewhere
  (`AppUpdatesService.swift`).
- Every download in an entry is rule-checked. One bad download drops the entry,
  as a bad `download` does today.

## Who writes it

- **Vitruvian Code's release** builds two more tool zips beside the
  all-Macs one: `vitruvian-code-tool-<ver>-arm64.zip` and `…-x86_64.zip`, each
  with its `.sha256` sidecar. Each holds `lipo -thin` copies of the already
  signed `bin/node` and `bin/tool`. Every slice of a universal Mach-O carries
  its own signature, so a thin copy stays validly signed.
  `check-packaged-app --tool-folder <folder> <arch>` checks each copy.
- **catalog-bump** learns an optional `architectures` map in `sources.json`
  (`{"arm64": "vitruvian-code-tool-{version}-arm64.zip", "x86_64": "…"}`). It
  checks each zip like the main one: same uploader, sidecar, GitHub digest, and
  Mach-Os containing that architecture. If every zip is present, it writes
  `downloads`; otherwise it removes `downloads`, so an old value can never
  outlive its release.

## Order

The three pieces ship independently, in any order:

| Piece | PR | Alone it… |
|---|---|---|
| Catalog schema, rules, bump, sources.json | catalog | accepts and writes `downloads`; does nothing until the zips exist |
| Atrium decoding and selection | atrium | installs `download` until an entry has `downloads` |
| Vitruvian Code release zips | code | uploads two more assets nobody reads yet |

## Later

When the all-Macs zip no longer fits under 256 MB, there is no valid
`download` left to publish. That is a later decision: make `download` optional
for new Atrium, accepting that old Atrium stops seeing Vitruvian Code updates
(it drops an entry it cannot decode and keeps the installed version). Not
needed now.
