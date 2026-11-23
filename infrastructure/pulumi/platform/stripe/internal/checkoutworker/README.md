# Checkout Worker

## Overview
Component package providing Cloudflare Turnstile widget, Checkout Session Worker script, and Workers Custom Domain provisioning for `infrastructure/pulumi/platform/stripe`.

## Interface
- `[config.go:Settings]`
- `[config.go:Validate]`
- `[config.go:CheckoutURL]`
- `[provision.go:Provision]`
- `[worker_script.go:WorkerScript]`

## Invariants
- Stays dormant when both `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` are unset; fails if only one is set.
- `Settings.Validate(account.ModeLive)` rejects `localhost` and `127.0.0.1` in `TurnstileDomains`.
- `worker.js` enforces exact `Origin` matching, verifies Turnstile `success === true`, `action === "donate"`, and expected `hostname` before creating a Stripe Checkout Session, and never uses wildcard CORS.

## Side Effects
- Provisions Cloudflare Turnstile widget, Workers script, and Workers Custom Domain (`donate-api.vitruviansoftware.dev` / `donate-api.dev.vitruviansoftware.dev`) when Cloudflare credentials are configured.

## Verification
- Run: `bazel test //infrastructure/pulumi/platform/stripe/...`
