<!--
Copyright (c) 2026 VitruvianSoftware

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
-->

# pagerduty

Manages the Vitruvian Software PagerDuty account (subdomain `vitruviansoftware`,
free tier) using the official `github.com/pulumi/pulumi-pagerduty/sdk/v4`
provider.

## What it manages

- **Responder lookup**: looks up the account owner (`responderEmail` in
  `Pulumi.production.yaml`) with `pagerduty.LookupUser`; the user is never
  created by Pulumi.
- **Escalation policy**: one `EscalationPolicy` with a single rule targeting
  the looked-up user, configured with `escalation.delayMinutes` and
  `escalation.loops` (without paid-tier team fields). The free plan allows only
  one escalation policy and every account starts with one called "Default", so
  production does not create a policy: `escalation.adoptId` names the existing
  one (`PS9GPWM`) and the first apply imports it, then renames and updates it
  in place. Leave `adoptId` empty only on an account with no policy yet.
- **Services and integrations**: for each entry in `services`, creates a
  `Service` bound to the escalation policy (`create_alerts_and_incidents`) and
  an `events_api_v2_inbound_integration` `ServiceIntegration` named
  `<service name> (Events API v2)`. Resource names derive from each service `key`
  so display name updates do not replace resources.
- **Stack outputs**: exports `<key>IntegrationKey` as a Pulumi secret (for
  downstream consumers such as the Sentry stack via `StackReference`), along
  with `<key>ServiceId` and `escalationPolicyId` in plain text.

The Pulumi project is named `vitruvian-pagerduty` rather than `pagerduty`
because `pagerduty:` is the provider's own config namespace (such as
`pagerduty:token`).

## Token and CI secret

The program creates an explicit PagerDuty provider using `PAGERDUTY_TOKEN` from
the environment if set, falling back to the Pulumi stack secret
`pagerduty:token`, and fails before registering any resource if neither is
present.

- **Bitwarden**: item `vitruviansoftware.pagerduty.com`, hidden field
  `PULUMI_API_KEY` (the field name says what the key is for: it is the
  PagerDuty REST API key this Pulumi stack uses).
- **CI**: supplied as the `PAGERDUTY_TOKEN` secret in the `pagerduty-production`
  GitHub Environment (declared in
  [repo-config](../repo-config/pagerduty_environments.go), bound by
  [delivery-pagerduty.yaml](../../../../.github/workflows/delivery-pagerduty.yaml),
  and seeded via [`//tools/sync-env-secrets`](../../../../tools/sync-env-secrets/README.md#pagerduty-production)).

## Preview and apply

Export the token from Bitwarden and preview the `production` stack:

```sh
export PAGERDUTY_TOKEN="<token-from-vitruviansoftware.pagerduty.com>"
bazel run //infrastructure/pulumi/platform/pagerduty:preview -- --stack production
```

Never run `:up` from a laptop. Changes to `production` are applied by CI after
merging to `main`.
