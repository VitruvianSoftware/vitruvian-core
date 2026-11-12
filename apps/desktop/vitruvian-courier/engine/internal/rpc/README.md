# Rpc

## Overview
Component package providing implementation for `apps/desktop/vitruvian-courier/engine/internal/rpc`.

## Interface
- `[dispatch.go:Dispatcher]`
- `[dispatch.go:NewDispatcher]`
- `[dispatch.go:Dispatch]`
- `[dispatch.go:ProtocolCode]`
- `[dispatch.go:Reason]`
- `[dispatch.go:Notifier]`
- `[dispatch.go:NewNotifier]`
- `[dispatch.go:Publish]`
- `[dispatch.go:Listeners]`
- `[methods.go:Error]`
- `[methods.go:Error]`
- `[search.go:Error]`
- `[search.go:Unwrap]`
- `[server.go:Protocol]`
- `[server.go:MaxFrameBytes]`
- `[server.go:NetworkInfo]`
- `[server.go:Deps]`
- `[server.go:Poker]`
- `[server.go:Serve]`

## Invariants
- [server.go:108]: `// Log gets the engine's own failures: an internal error (the method and the ...`
- [server.go:349]: `// run calls one method, turning a panic into an internal error so one bad re...`
- [server.go:350]: `// panic is logged with its stack.`

## Side Effects
- [dispatch.go:15]: `// requests run, and no query is written twice.`
- [feed.go:10]: `// changed is the params of a changed notification: what changed, so the app ...`
- [messages.go:263]: `// roomMembers lists the people in a chat whose name matches query, for a men...`
- [messages.go:264]: `// me, not the bridge's bot), in the chat (not left or banned), by name. Each...`
- [messages.go:265]: `// folds it (accents, case), must begin a word of the name; an empty query ma...`
- [methods.go:164]: `return invalidParams("cursor is not one this query handed out"), false`
- [methods.go:285]: `"search.query": searchQuery,`
- [organise.go:272]: `q.After = *p.Cursor // the store refuses a cursor of another query: ErrBadCursor`
- [people.go:19]: `Query     *string `json:"query"``
- [people.go:35]: `query := ""`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-courier/engine/internal/rpc/...`
