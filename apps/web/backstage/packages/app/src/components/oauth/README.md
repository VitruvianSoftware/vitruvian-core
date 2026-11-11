# Oauth

## Overview
Component package providing implementation for `apps/web/backstage/packages/app/src/components/oauth`.

## Interface
- `[OAuth2AuthorizePage.tsx:SessionDetails]`
- `[OAuth2AuthorizePage.tsx:OAuth2AuthorizePage]`

## Invariants
- None

## Side Effects
- [OAuth2AuthorizePage.tsx:67]: `const res = await fetchApi.fetch(`
- [OAuth2AuthorizePage.tsx:75]: ``Failed to fetch session: ${res.statusText}`,`
- [OAuth2AuthorizePage.tsx:87]: `const res = await fetchApi.fetch(`

## Verification
- Run: `bazel test //apps/web/backstage/packages/app/src/components/oauth/...`
