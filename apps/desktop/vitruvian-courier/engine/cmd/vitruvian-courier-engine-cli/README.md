# Vitruvian Courier Engine Cli

## Overview
Component package providing implementation for `apps/desktop/vitruvian-courier/engine/cmd/vitruvian-courier-engine-cli`.

## Interface
- `[login.go:Line]`
- `[login.go:Secret]`
- `[login.go:Confirm]`

## Invariants
- None

## Side Effects
- [login.go:18]: `"go.mau.fi/util/curl"`
- [login.go:175]: `// maxCookieFile caps how much of a cookie file is read. A browser's "copy as...`
- [login.go:179]: `// holding a cURL command or a JSON object copied from the browser's develope...`
- [main.go:70]: `data := fs.String("data", "", "data directory (default ~/Library/Application ...`
- [main.go:71]: `network := fs.String("network", "", "network to link (link only): "+networkNa...`
- [main.go:72]: `flow := fs.String("flow", "", "login flow to use (link only; default: the net...`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-courier/engine/cmd/vitruvian-courier-engine-cli/...`
