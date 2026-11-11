# Imessage

## Overview
Component package providing implementation for `apps/desktop/courier/engine/internal/imessage`.

## Interface
- `[chatdb.go:DefaultChatDBPath]`
- `[chatdb.go:AppleTimeToTime]`
- `[chatdb.go:TimeToAppleNano]`
- `[chatdb.go:ExtractAttributedBodyText]`
- `[chatdb.go:EncodeAttributedBody]`
- `[chatdb.go:NormalizeAssociatedGUID]`
- `[chatdb.go:IsTapbackType]`
- `[chatdb.go:TapbackFromRow]`
- `[chatdb.go:EmojiToTapbackType]`
- `[chatdb.go:ExpandAttachmentPath]`
- `[chatdb.go:ChatRecord]`
- `[chatdb.go:IsDM]`
- `[chatdb.go:HandleRecord]`
- `[chatdb.go:AttachmentRecord]`
- `[chatdb.go:EffectiveFileName]`
- `[chatdb.go:MessageRecord]`
- `[chatdb.go:ChatDB]`
- `[chatdb.go:OpenChatDB]`
- `[chatdb.go:Close]`
- `[chatdb.go:CheckAccess]`

## Invariants
- None

## Side Effects
- [chatdb.go:407]: `db   *sql.DB`
- [chatdb.go:442]: `db, err := sql.Open("sqlite3", uri)`
- [chatdb.go:451]: `_ = db.Close()`
- [connector.go:10]: `"net/http"`
- [send.go:12]: `"os/exec"`
- [send.go:116]: `// ExecFunc executes the osascript command; if nil, exec.CommandContext is used.`
- [send.go:132]: `cmd := exec.CommandContext(ctx, "/usr/bin/osascript", args...)`

## Verification
- Run: `bazel test //apps/desktop/courier/engine/internal/imessage/...`
