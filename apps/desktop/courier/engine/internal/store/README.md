# Store

## Overview
Component package providing implementation for `apps/desktop/courier/engine/internal/store`.

## Interface
- `[accounts.go:SubAccount]`
- `[accounts.go:SetRoomSpace]`
- `[accounts.go:UpsertSubAccount]`
- `[accounts.go:SubAccounts]`
- `[accounts.go:UpdateSubAccount]`
- `[accounts.go:SyncBotSubAccounts]`
- `[accounts.go:RemoveAccountData]`
- `[apitokens.go:APIToken]`
- `[apitokens.go:CleanClientName]`
- `[apitokens.go:CreateAPIToken]`
- `[apitokens.go:ErrLastUsedNotSaved]`
- `[apitokens.go:LookupAPIToken]`
- `[apitokens.go:ListAPITokens]`
- `[apitokens.go:RevokeAPIToken]`
- `[apitokens.go:SetAPITokenCanSend]`
- `[apitokens.go:LocalAPISettings]`
- `[apitokens.go:Setting]`
- `[apitokens.go:SetSetting]`
- `[apitokens.go:LocalAPI]`
- `[apitokens.go:SetLocalAPI]`
- Subdirectory: [storetest](./storetest/README.md)

## Invariants
- [spaces.go:111]: `panic("no place rule for space " + id)`

## Side Effects
- [accounts.go:34]: `res, err := s.db.Exec(`
- [accounts.go:69]: `_, err := s.db.Exec(`
- [accounts.go:88]: `rows, err := s.db.Query(`
- [apitokens.go:98]: `if _, err = s.db.Exec(ctx, `INSERT INTO api_tokens (id, name, hash, can_send,...`
- [apitokens.go:122]: `lastUsed  sql.NullInt64`
- [apitokens.go:124]: `err := s.db.QueryRow(ctx, `SELECT id, name, hash, can_send, created_ms, last_...`
- [autoarchive.go:104]: `err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {`
- [autoarchive.go:107]: `err := s.db.QueryRow(ctx, "SELECT 1 FROM labels WHERE label_id=$1", labelID)....`
- [autoarchive.go:108]: `if errors.Is(err, sql.ErrNoRows) {`
- [bookmarks.go:25]: `err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {`

## Verification
- Run: `bazel test //apps/desktop/courier/engine/internal/store/...`
