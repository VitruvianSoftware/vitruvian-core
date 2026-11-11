# Proxy

## Overview
Component package providing implementation for `apps/web/backstage/packages/backend/src/proxy`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [argocdProxyConfig.test.ts:113]: `/^http:\/\/argocd-server\.argocd\.svc\.cluster\.local\b/,`
- [observabilityProxyConfig.test.ts:85]: `/^http:\/\/(thanos-query|prometheus-server)\.monitoring\.svc\.cluster\.local/,`
- [observabilityProxyConfig.test.ts:134]: `/^http:\/\/tempo\.opentelemetry\.svc\.cluster\.local/,`
- [observabilityProxyConfig.test.ts:142]: `/^http:\/\/tempo\.opentelemetry\.svc\.cluster\.local/,`

## Verification
- Run: `bazel test //apps/web/backstage/packages/backend/src/proxy/...`
