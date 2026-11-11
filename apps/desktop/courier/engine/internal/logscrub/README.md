# Logscrub

## Overview
Component package providing implementation for `apps/desktop/courier/engine/internal/logscrub`.

## Interface
- `[logscrub.go:Writer]`
- `[logscrub.go:New]`
- `[logscrub.go:Write]`
- `[logscrub.go:Line]`
- `[logscrub.go:Scrub]`
- `[logscrub.go:Redact]`
- `[stack.go:ScrubPath]`
- `[stack.go:ScrubStartupError]`
- `[stack.go:ScrubExportLine]`
- `[stack.go:ScrubStderrExport]`
- `[stack.go:RollingFile]`
- `[stack.go:OpenRollingFile]`
- `[stack.go:File]`
- `[stack.go:Write]`
- `[stack.go:Close]`

## Invariants
- [logscrub.go:39]: `// error, panic, stack, caller) are redacted like every other string. Each ke...`
- [logscrub.go:69]: `"panic":            true, // a recovered panic's value, redacted`
- [logscrub.go:198]: `"trace": true, "debug": true, "info": true, "warn": true, "error": true, "fat...`
- [stack.go:32]: `// Go stack frame call line: "pkg/path.(*Type).Method(0x14000123456, 0x102938...`
- [stack.go:34]: `frameCallRE = regexp.MustCompile(`^((?:created by )?(?:panic|[A-Za-z0-9_./@-]...`
- [stack.go:134]: `// 3. Panic / fatal header -> replace payload with [redacted] so panic(userJI...`

## Side Effects
- [logscrub.go:34]: `Path   = "[path]"   // a URL's path and query`
- [logscrub.go:56]: `"method":          true, // the engine's protocol method ("room.events"), an ...`
- [logscrub.go:284]: `// Google Chat WebChannel query tokens (gsessionid, AID, SID, RID).`

## Verification
- Run: `bazel test //apps/desktop/courier/engine/internal/logscrub/...`
