# Gchat

## Overview
Component package providing implementation for `apps/desktop/vitruvian-courier/engine/internal/gchat`.

## Interface
- `[client.go:Client]`
- `[client.go:Connect]`
- `[client.go:Disconnect]`
- `[client.go:IsLoggedIn]`
- `[client.go:LogoutRemote]`
- `[client.go:IsThisUser]`
- `[client.go:GetChatInfo]`
- `[client.go:GetUserInfo]`
- `[client.go:GetCapabilities]`
- `[client.go:FillBridgeState]`
- `[connector.go:UserLoginMetadata]`
- `[connector.go:PortalMetadata]`
- `[connector.go:GhostMetadata]`
- `[connector.go:MessageMetadata]`
- `[connector.go:ReactionMetadata]`
- `[connector.go:Connector]`
- `[connector.go:NewConnector]`
- `[connector.go:Init]`
- `[connector.go:Start]`
- `[connector.go:GetName]`
- Subdirectory: [pb](./pb/README.md)

## Invariants
- [media.go:140]: `return "", nil, errors.New("Google Chat image attachments require an image MI...`
- [media.go:146]: `return "", nil, errors.New("Google Chat GIF attachments require an image/gif ...`
- [media.go:152]: `return "", nil, errors.New("Google Chat video attachments require a video MIM...`

## Side Effects
- [client.go:329]: `if c.UserLogin.Bridge != nil && c.UserLogin.Bridge.DB != nil && c.UserLogin.B...`
- [client.go:330]: `if existing, err := c.UserLogin.Bridge.DB.Message.GetFirstPartByID(ctx, c.Use...`
- [client.go:465]: `// Fetch off the event path, then apply under ghostMu so the write`
- [connector.go:83]: `if c.Bridge == nil || c.Bridge.DB == nil || c.Bridge.DB.Database == nil {`
- [connector.go:86]: `if _, err := c.Bridge.DB.Exec(ctx, clearSelfThreadRootsSQL, c.Bridge.ID); err...`
- [media.go:10]: `"net/http"`
- [media.go:364]: `snifferMime := http.DetectContentType(data)`
- [sync.go:394]: `if c.UserLogin.Bridge.DB != nil && c.UserLogin.Bridge.DB.Database != nil {`
- [sync.go:395]: `rows, err := c.UserLogin.Bridge.DB.Query(ctx, `SELECT id, name FROM portal WH...`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-courier/engine/internal/gchat/...`
