# Utils

## Overview
Component package providing implementation for `apps/web/oauth-user-inspector/frontend/utils`.

## Interface
- `[apiEndpoints.ts:getProviderEndpoints]`
- `[oauthSession.ts:ByoCredentials]`
- `[oauthSession.ts:StoredAuthMeta]`
- `[oauthSession.ts:MissingCredentialsError]`
- `[oauthSession.ts:buildAuthMeta]`
- `[oauthSession.ts:buildRefreshRequest]`
- `[oauthSession.ts:buildRevokeRequest]`
- `[oauthSession.ts:parseAuthMeta]`
- `[userinfoRequest.ts:UserinfoProvider]`
- `[userinfoRequest.ts:UserinfoRequestOptions]`
- `[userinfoRequest.ts:UserinfoFetchMode]`
- `[userinfoRequest.ts:UserinfoRequestInit]`
- `[userinfoRequest.ts:UserinfoRequest]`
- `[userinfoRequest.ts:buildUserinfoRequest]`

## Invariants
- None

## Side Effects
- [userinfoRequest.ts:28]: `* `Access-Control-Allow-Origin` header, so a direct cross-origin browser fetch`
- [userinfoRequest.ts:30]: `* "Failed to fetch". So LinkedIn's userinfo MUST be routed through our`
- [userinfoRequest.ts:35]: `* This module is intentionally PURE (no `fetch`, no DOM, no `localStorage`) so`

## Verification
- Run: `bazel test //apps/web/oauth-user-inspector/frontend/utils/...`
