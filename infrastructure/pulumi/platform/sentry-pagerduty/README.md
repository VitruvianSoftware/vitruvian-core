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

# sentry-pagerduty

Wires our self-hosted Sentry (`https://sentry.lab.ipv1337.dev`, org `sentry`)
to page PagerDuty on high-priority issues in every project, using
`jianyuan/terraform-provider-sentry` v0.15.8 bridged into Pulumi Go via the
parameterized `terraform-provider` package (`sdks/sentry`).

## What it manages

- **Org integration lookup**: looks up Sentry's PagerDuty organization
  integration (`Vitruvian Software`, provider key `pagerduty`).
- **PagerDuty service row**: reads the secret `sentryIntegrationKey` output from
  the `ipv1337/vitruvian-pagerduty/production` stack via `StackReference` and
  manages one `sentry_integration_pagerduty` service row (`Sentry`).
- **Per-project high-priority alerts**: enumerates every project in org `sentry`
  via `sentry_all_projects` (excluding `internal`, Sentry's self-monitoring
  project so internal Sentry telemetry never pages), looks up each project's
  default error monitor (`sentry_project_error_monitor`), and reconciles one
  workflow-engine `sentry_alert` (`<slug>: page PagerDuty on high-priority issues`)
  that triggers on `first_seen_event` or `reappeared_event`, filtered to issues
  with priority >= 75 (`issue_priority_greater_or_equal >= 75`, high priority).
  Projects added to Sentry later are picked up on the next apply.

## Known gap

An existing issue that rises to high priority later will **not** page PagerDuty.
Only issues that are first seen at high priority (`first_seen_event` with
priority >= 75), or that reappear (`reappeared_event`, filtered to priority >=
75), will page.

`jianyuan/terraform-provider-sentry` v0.15.8 cannot express priority-escalation
triggers in `triggerConditions`: as documented in
`sdks/sentry/sentry/alert.go:26` (and repeated on `AlertArgs` at line 176),
Sentry's `newHighPriorityIssue`, `existingHighPriorityIssue`, and
`issueResolutionChange` trigger condition types are "not natively supported by
this provider".

## Why a separate stack

- `infrastructure/pulumi/platform/sentry` uses `pulumiverse/pulumi-sentry` v0.0.9
  under package name `sentry`; adding a second `sentry` provider there would
  collide.
- Sentry 26.10.1 removed `/api/0/projects/{org}/{project}/rules/` (returns 404),
  so legacy `sentry_issue_alert` resources no longer work and alerts must use
  Sentry's workflow engine (`POST /api/0/organizations/{org}/workflows/`) via
  `sentry_alert` in `jianyuan/sentry` v0.15.8.

## Prerequisites

1. Install the `"Vitruvian Software"` PagerDuty organization integration in
   Sentry:
   ```sh
   export SENTRY_TOKEN=...   # Bitwarden item sentry.lab.ipv1337.dev, field SENTRY_TOKEN
   bazel run //tools/sentry:pagerduty-install -- --subdomain vitruviansoftware --name "Vitruvian Software"
   ```
2. Apply `infrastructure/pulumi/platform/pagerduty` (`production` stack) so
   `ipv1337/vitruvian-pagerduty/production` exports `sentryIntegrationKey`.

## CI apply and local preview

This stack is applied automatically by
[`.github/workflows/sentry-apply.yaml`](../../../../.github/workflows/sentry-apply.yaml)
against the `production` stack, immediately after
[`infrastructure/pulumi/platform/sentry`](../sentry/README.md) so new projects
receive PagerDuty alert rules in the same run:

- **Triggers**: `push` to `main` (touching `infrastructure/pulumi/platform/sentry/**`,
  `infrastructure/pulumi/platform/sentry-pagerduty/**`, `.github/workflows/sentry-apply.yaml`,
  `.github/actions/homelab-tunnel-setup/**`, `.github/actions/pulumi-summary/**`,
  or the Pulumi CI helper binaries),
  a 6-hour `schedule` (picking up Sentry projects created outside git), and
  `workflow_dispatch` (`action: preview|up`, defaulting to `preview`).
- **Environment**: `sentry-production` (main-only, no required reviewer,
  declared in [`repo-config`](../repo-config/sentry_environments.go)). Holds
  `SENTRY_TOKEN` (minted with `bazel run //tools/sentry:ci-token`) and
  `HEADSCALE_CI_AUTHKEY` (synced via
  [`//tools/sync-env-secrets`](../../../../tools/sync-env-secrets/README.md#sentry-production)).
  If `SENTRY_TOKEN` is not seeded yet, the workflow emits a `::notice::` and
  exits `0`.
- **Non-destructive plan guard**: before `pulumi up`, the job runs
  `pulumi preview --json` and passes it to `//tools/pulumi:refuse-destructive-plan`.
  If any `delete`, `replace`, `create-replacement`, or `delete-replaced` step is
  planned, the job fails and refuses to apply; deletions and replacements must be
  performed deliberately by a human.
- **Route**: joins the Headscale mesh (`tag:ci`) via
  [`.github/actions/homelab-tunnel-setup`](../../../../.github/actions/homelab-tunnel-setup/action.yml)
  and forwards `sentry.lab.ipv1337.dev:443` through the Envoy Gateway's
  `https-sentry` NodePort (`:31103`).

For local debugging on the tailnet, export `SENTRY_TOKEN` from Bitwarden
(`sentry.lab.ipv1337.dev`, hidden field `SENTRY_TOKEN`) and run preview:

```sh
export SENTRY_TOKEN="<token-from-bitwarden>"
bazel run //infrastructure/pulumi/platform/sentry-pagerduty:preview -- --stack production
```

## Regenerating the Sentry SDK

When updating `terraform-provider` or `jianyuan/sentry` in `Pulumi.yaml`:

```sh
bazel run //tools/pulumi:pulumi-cmd -- infrastructure/pulumi/platform/sentry-pagerduty package add --non-interactive terraform-provider registry.terraform.io/jianyuan/sentry 0.15.8
bazel run //tools/gomod:tidy -- infrastructure/pulumi/platform/sentry-pagerduty/go.mod
```

Then restore the MIT header in `Pulumi.yaml`, set `go 1.26.10` and `github.com/pulumi/pulumi/sdk/v3 v3.274.1` in `sdks/sentry/go.mod`, and replace `return nil, err` with `return "", err` in `sdks/sentry/sentry/{assertion,op*}.go` (working around a `pulumi-language-go` v3.276.0 codegen bug for `(string, error)` functions).
