# Frontend

## Overview
Component package providing implementation for `apps/web/oauth-user-inspector/frontend`.

## Interface
- `[fieldDocs.ts:FieldDoc]`
- `[fieldDocs.ts:providerDocs]`
- `[fieldDocs.ts:getFieldDoc]`
- `[fieldDocs.ts:getAllFieldDocs]`
- `[types.ts:ProviderGitHubUser]`
- `[types.ts:ProviderGoogleUser]`
- `[types.ts:ProviderGitLabUser]`
- `[types.ts:ProviderAuth0User]`
- `[types.ts:ProviderZitadelUser]`
- `[types.ts:ProviderLinkedInUser]`
- `[types.ts:AuthProvider]`
- `[types.ts:AppUser]`
- `[types.ts:TokenRefreshRequest]`
- `[types.ts:TokenRefreshResponse]`
- `[types.ts:TokenRevocationRequest]`
- `[types.ts:TokenRevocationResponse]`
- `[types.ts:ApiEndpoint]`
- `[types.ts:ApiExploreRequest]`
- `[types.ts:OAuthErrorGuide]`
- `[types.ts:EnhancedOAuthError]`
- Subdirectory: [components](./components/README.md)
- Subdirectory: [design-system](./design-system/README.md)
- Subdirectory: [utils](./utils/README.md)

## Invariants
- None

## Side Effects
- [App.tsx:123]: `// Fetch hosted OAuth availability (secrets existence)`
- [App.tsx:127]: `const resp = await fetch("/api/oauth-hosted/availability");`
- [App.tsx:140]: `const resp = await fetch("/api/health");`
- [vite.config.ts:41]: `target: "http://localhost:8080",`

## Verification
- Run: `bazel test //apps/web/oauth-user-inspector/frontend/...`
