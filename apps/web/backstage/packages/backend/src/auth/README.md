# Auth

## Overview
Component package providing implementation for `apps/web/backstage/packages/backend/src/auth`.

## Interface
- `[githubOrgSignIn.ts:DEFAULT_ALLOWED_ORG]`
- `[githubOrgSignIn.ts:MembershipFetcher]`
- `[githubOrgSignIn.ts:githubMembershipFetcher]`
- `[githubOrgSignIn.ts:OrgMembershipError]`
- `[githubOrgSignIn.ts:assertActiveOrgMember]`
- `[module.ts:authModuleGithubOrgProvider]`

## Invariants
- None

## Side Effects
- [githubOrgSignIn.ts:29]: `* the check is expressed against an interface rather than global fetch.`
- [githubOrgSignIn.ts:40]: `const res = await fetch(`
- [mcpAuthRedirectConfig.test.ts:30]: `// recursive wildcard subpaths ('http://localhost:*/**' and 'http://127.0.0.1...`
- [mcpAuthRedirectConfig.test.ts:32]: `// (e.g. 'http://localhost:15466/oauth/callback') are accepted.`
- [mcpAuthRedirectConfig.test.ts:82]: `expect(cimdRedirects).toContain("http://localhost:*/**");`

## Verification
- Run: `bazel test //apps/web/backstage/packages/backend/src/auth/...`
