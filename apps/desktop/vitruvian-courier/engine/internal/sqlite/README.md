# Sqlite

## Overview
Component package providing implementation for `apps/desktop/courier/engine/internal/sqlite`.

## Interface
- `[open.go:PrivateDir]`
- `[open.go:Open]`

## Invariants
- None

## Side Effects
- [open.go:42]: `if _, err = db.Exec(context.Background(), "PRAGMA temp_store = MEMORY"); err ...`
- [open.go:43]: `db.Close()`
- [open.go:48]: `if err = os.Chmod(p, 0o600); err != nil && !errors.Is(err, fs.ErrNotExist) {`

## Verification
- Run: `bazel test //apps/desktop/courier/engine/internal/sqlite/...`
