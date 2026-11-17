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
- **On-call schedule**: one shift-based `Schedulev2` (the legacy `Schedule`
  resource is deprecated), configured under `schedule`. A single event repeats
  every `shiftDays` from a fixed `start`, and `members` (emails of existing
  PagerDuty users, looked up, never created) take it in turns. An empty
  `members` list means the responder alone, which is what production runs
  today. The free plan allows one schedule. To add someone, invite them in
  PagerDuty first (the free plan allows five users), then add their email.
- **Escalation policy**: one `EscalationPolicy` with a single rule targeting
  the on-call schedule (whoever is on call), configured with `escalation.delayMinutes` and
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
- **Urgency**: every service uses severity-based urgency, so an event's own
  severity decides how loudly PagerDuty notifies. `critical` and `error` are
  high urgency (phone, escalates); `warning` and `info` are low urgency.
- **Stack outputs**: exports `<key>IntegrationKey` as a Pulumi secret (for
  downstream consumers such as the Sentry stack via `StackReference`), along
  with `<key>ServiceId` and `escalationPolicyId` in plain text. `repo-config`
  reads `ciIntegrationKey` the same way and stores it as the repository secret
  `PAGERDUTY_CI_ROUTING_KEY`, which `notify-ci-issues` sends CI failures with.

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
  It was created on the account's API Access Keys page
  (`/api_keys`), so it is an account-level key, not tied to one person's
  login. It can change anything in the account. To rotate it: create a new
  key on that page, update the Bitwarden field and the environment secret
  (below), then delete the old key.
- **Seeding order**: store `PAGERDUTY_TOKEN` only after repo-config has
  created the `pagerduty-production` environment and you have checked it is
  limited to `main`. Saving a secret into an environment that does not exist
  yet makes GitHub create it unprotected.
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

## Homelab alerts (Alertmanager)

The `cluster`, `data` and `apps` services take the homelab cluster's
Prometheus alerts. Each alert rule in
[`gitops/argocd/platform/prometheus/applicationset.yaml`](../../../../gitops/argocd/platform/prometheus/applicationset.yaml)
has a `pagerduty_service` label naming its service, and Alertmanager has a
`pagerduty-<service>` receiver for each. `severity: page` goes to PagerDuty as
`critical` and `severity: warning` as `warning`. ntfy still gets a copy of
every alert, so it keeps working if PagerDuty does not.

The rule tests (`tools/ci/prometheus-rule-tests`) fail if an actionable rule
has no label, or one with no receiver.

The keys reach the cluster as the `alertmanager-pagerduty-keys` SealedSecret.
After the stack has applied a new or changed service, reseal them from the
stack's outputs and commit the file:

```sh
bazel run //infrastructure/pulumi/platform/pagerduty:stack -- output --json --show-secrets --stack production \
  | bazel run //tools/gitops:seal-alert-pagerduty
```

To add a service for the cluster, add it to `services` here, to
`PAGERDUTY_SERVICES` in `tools/gitops/src/ops/seal.rs`, and as a receiver and
route in the Alertmanager config.
