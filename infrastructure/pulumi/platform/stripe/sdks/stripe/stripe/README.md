# Stripe

## Overview
Component package providing implementation for `infrastructure/pulumi/platform/stripe/sdks/stripe/stripe`.

## Interface
- `[applePayDomain.go:ApplePayDomain]`
- `[applePayDomain.go:NewApplePayDomain]`
- `[applePayDomain.go:GetApplePayDomain]`
- `[applePayDomain.go:ApplePayDomainState]`
- `[applePayDomain.go:ElementType]`
- `[applePayDomain.go:ApplePayDomainArgs]`
- `[applePayDomain.go:ElementType]`
- `[applePayDomain.go:ApplePayDomainInput]`
- `[applePayDomain.go:ElementType]`
- `[applePayDomain.go:ToApplePayDomainOutput]`
- `[applePayDomain.go:ToApplePayDomainOutputWithContext]`
- `[applePayDomain.go:ApplePayDomainOutput]`
- `[applePayDomain.go:ElementType]`
- `[applePayDomain.go:ToApplePayDomainOutput]`
- `[applePayDomain.go:ToApplePayDomainOutputWithContext]`
- `[applePayDomain.go:Created]`
- `[applePayDomain.go:DomainName]`
- `[applePayDomain.go:Livemode]`
- `[applePayDomain.go:Object]`
- `[billingAlert.go:BillingAlert]`
- Subdirectory: [config](./config/README.md)
- Subdirectory: [internal](./internal/README.md)

## Invariants
- [paymentMethodDomain.go:26]: `// Whether this payment method domain is enabled. If the domain is not enable...`
- [paymentMethodDomain.go:91]: `// Whether this payment method domain is enabled. If the domain is not enable...`
- [paymentMethodDomain.go:116]: `// Whether this payment method domain is enabled. If the domain is not enable...`
- [webhookEndpoint.go:28]: `// The list of events to enable for this endpoint. `['*']` indicates that all...`
- [webhookEndpoint.go:102]: `// The list of events to enable for this endpoint. `['*']` indicates that all...`
- [webhookEndpoint.go:129]: `// The list of events to enable for this endpoint. `['*']` indicates that all...`

## Side Effects
- None

## Verification
- Run: `bazel test //infrastructure/pulumi/platform/stripe/sdks/stripe/stripe/...`
