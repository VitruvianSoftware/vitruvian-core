# Permissions

## Overview
Component package providing implementation for `apps/web/backstage/packages/backend/src/permissions`.

## Interface
- `[module.ts:permissionModuleVitruvianPolicy]`
- `[vitruvianPolicy.ts:DEFAULT_ADMIN_ENTITY_REFS]`
- `[vitruvianPolicy.ts:VitruvianPermissionPolicy]`

## Invariants
- None

## Side Effects
- [vitruvianPolicy.test.ts:42]: `const query = (p: Permission): PolicyQuery =>`
- [vitruvianPolicy.test.ts:77]: `query(permission("catalog.entity.read", "read")),`
- [vitruvianPolicy.test.ts:91]: `query(permission(name, action)),`

## Verification
- Run: `bazel test //apps/web/backstage/packages/backend/src/permissions/...`
