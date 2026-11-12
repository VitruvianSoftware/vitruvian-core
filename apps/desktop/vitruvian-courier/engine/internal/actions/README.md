# Actions

## Overview
Component package providing implementation for `apps/desktop/vitruvian-courier/engine/internal/actions`.

## Interface
- `[actions.go:MaxFileBytes]`
- `[actions.go:DefaultLoginWait]`
- `[actions.go:MaxTextBytes]`
- `[actions.go:ReasonUnreadable]`
- `[actions.go:ReasonNotConnected]`
- `[actions.go:HoldWindows]`
- `[actions.go:SendOptions]`
- `[actions.go:Source]`
- `[actions.go:SourceOf]`
- `[actions.go:Actions]`
- `[actions.go:New]`
- `[actions.go:WaitForLogin]`
- `[actions.go:WaitForChat]`
- `[actions.go:SendText]`
- `[actions.go:Send]`
- `[actions.go:SendFile]`
- `[actions.go:SendFileWith]`
- `[actions.go:React]`
- `[actions.go:MarkRead]`
- `[actions.go:Retry]`

## Invariants
- None

## Side Effects
- [actions.go:29]: `"net/http"`
- [actions.go:122]: `// Only when explicitly false does the engine fetch OpenGraph metadata for th...`
- [actions.go:165]: `linkClient   *http.Client`
- [chatinfo.go:247]: `if err := os.WriteFile(destPath, buf.Bytes(), 0o600); err != nil {`
- [linkpreview.go:13]: `"net/http"`
- [linkpreview.go:39]: `// SetLinkPreviewHTTPClient overrides the HTTP client used when DisableLinkPr...`
- [linkpreview.go:41]: `func (a *Actions) SetLinkPreviewHTTPClient(c *http.Client) {`
- [privacy.go:353]: `ups, err := h.Bridge.DB.UserPortal.GetAllForUserInPortal(ctx, ids.Me, portal....`
- [startchat.go:40]: `// ListContacts queries the connected bridge account(s) for their contact lis...`
- [startchat.go:42]: `func (a *Actions) ListContacts(ctx context.Context, network, accountID, query...`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-courier/engine/internal/actions/...`
