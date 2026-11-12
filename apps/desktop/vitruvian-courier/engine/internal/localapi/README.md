# Localapi

## Overview
Component package providing implementation for `apps/desktop/vitruvian-courier/engine/internal/localapi`.

## Interface
- `[pair.go:PairEnded]`
- `[pair.go:ErrNoSuchPairing]`
- `[pair.go:PairRequest]`
- `[pair.go:SetPairTimeout]`
- `[pair.go:SetPairCooldown]`
- `[pair.go:AnswerPairing]`
- `[schemas.go:SearchDocsText]`
- `[server.go:Dispatcher]`
- `[server.go:Publisher]`
- `[server.go:Config]`
- `[server.go:Status]`
- `[server.go:Server]`
- `[server.go:SetAppLocked]`
- `[server.go:AppLocked]`
- `[server.go:SetIdleTimeout]`
- `[server.go:New]`
- `[server.go:MCP]`
- `[server.go:Handler]`
- `[server.go:Status]`
- `[server.go:Addr]`

## Invariants
- [rest.go:81]: `outcome = "panic"`
- [rest.go:85]: `if outcome == "panic" {`
- [tools.go:114]: `panic("localapi: no implementation for tool " + def.name)`
- [tools.go:120]: `// wrap runs one tool: its result as one JSON text block, or its failure as a...`
- [tools.go:128]: `outcome = "panic"`

## Side Effects
- [markdown.go:16]: `// _italic_), ~~strikethrough~~ and [links](https://…) (http, https or mailto...`
- [markdown.go:201]: `// link formats [text](address) as a link, if address is http, https or mailto.`
- [markdown.go:219]: `!(strings.HasPrefix(lower, "http://") || strings.HasPrefix(lower, "https://")...`
- [pair.go:12]: `"net/http"`
- [pair.go:137]: `func (s *Server) servePair(w http.ResponseWriter, r *http.Request) {`
- [pair.go:138]: `if r.Method != http.MethodPost {`
- [rest.go:11]: `"net/http"`
- [rest.go:75]: `func (s *Server) rest(name string, f func(ctx context.Context, q url.Values) ...`
- [rest.go:76]: `return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {`
- [schemas.go:32]: `"query":{"type":"string","description":"Words to look for. Messages need at l...`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-courier/engine/internal/localapi/...`
