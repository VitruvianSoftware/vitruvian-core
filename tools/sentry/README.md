# sentry

Operational CLI tools for self-hosted Sentry: PagerDuty integration bootstrap (`pagerduty-install`), synthetic alert verification (`send-test-event`), and CI internal integration provisioning and verification (`ci-integration`).

## Bootstrap PagerDuty integration (`pagerduty-install`)

One-shot, idempotent bootstrap for self-hosted Sentry's PagerDuty organization integration without registering a PagerDuty OAuth app.

```sh
bazel run //tools/sentry:pagerduty-install -- --subdomain vitruviansoftware --name "Vitruvian Software"
```

Pass `--url` (default `https://sentry.lab.ipv1337.dev`) or `--org` (default `sentry`) to target another instance or organization. Run `--help` for all options.

## Why no PagerDuty app

Sentry's browser setup flow redirects through a registered PagerDuty OAuth app, which self-hosted Sentry lacks out of the box. On Sentry 26.10.1, `POST /api/0/organizations/<org>/pipeline/integration_pipeline/` accepts the PagerDuty account `subdomain` and display `name` directly over two Django-session-coupled calls, using an empty `integration_keys` list (services are added later by Pulumi).

## One-time use and idempotency

The tool first queries `GET /api/0/organizations/<org>/integrations/?provider_key=pagerduty`. If a PagerDuty integration is already present, it prints `already installed: id=<id> name=<name>` and exits `0` without mutating Sentry. Otherwise it initializes the pipeline, submits the configuration step using the returned session cookie, verifies the integration appears, and prints `installed: id=<id> name=<name>`.

## Token needed

Set `SENTRY_TOKEN` in the environment to a **user** auth token (prefix `sntryu_`) with `org:write` plus all scopes granted by `ci-integration` (`alerts:read`, `alerts:write`, `org:read`, `org:write`, `project:read`, `project:write`, `team:read`, `team:write`, since `SentryAppParser.validate_scopes` requires the caller to hold every scope granted to the internal integration; `org:write` also authorizes `pagerduty-install`). Export it from Bitwarden item `sentry.lab.ipv1337.dev`, field `SENTRY_TOKEN` (see [infrastructure/pulumi/platform/sentry/README.md](../../infrastructure/pulumi/platform/sentry/README.md)). Tokens are passed to `curl` only via stdin config (`-K -`) and never placed on the command line, in child environments, or in logs. For `pagerduty-install`, pipeline cookies live in a mode-`0600` file inside a temporary directory deleted on exit.

## Send a synthetic test event (`send-test-event`)

To verify that Sentry → PagerDuty alerting fires end to end, send one synthetic error event to a Sentry project's envelope endpoint:

```sh
bazel run //tools/sentry:send-test-event -- --dsn https://<public_key>@<host>/<project_id> [--level fatal] [--message "Synthetic PagerDuty test"]
```

Each invocation generates a fresh random `event_id` and includes it in `fingerprint`, so Sentry creates a **real new issue** (triggering first-seen alert rules) rather than grouping into an existing issue. Resolve the resulting issue in Sentry afterwards. It sends `User-Agent: sentry.rust/0.35.0` so Cloudflare in front of public ingest accepts the request.

## Reconcile and check CI internal integration (`ci-integration`)

Idempotently ensure self-hosted Sentry has an internal integration (`isInternal=true`, `status: "internal"`) scoped for CI applies of `infrastructure/pulumi/platform/sentry` and `infrastructure/pulumi/platform/sentry-pagerduty`, and print its slug and UI link:

```sh
bazel run //tools/sentry:ci-integration -- [--name vitruvian-ci] [--url https://sentry.lab.ipv1337.dev] [--org sentry]
```

Granted scopes (`REQUIRED_SCOPES`, closed under `SENTRY_SCOPE_HIERARCHY_MAPPING` with no `*:admin` scopes so CI cannot delete projects or teams):

- `project:read` — `sentry` & `sentry-pagerduty`: read projects, DSN client keys, and dashboard widget project filters.
- `project:write` — `sentry`: create/update projects, attach/detach project teams, create/update DSN client keys, and enable inbound data filters.
- `team:read` — `sentry`: read teams.
- `team:write` — `sentry`: create and update teams.
- `org:read` — `sentry` & `sentry-pagerduty`: read org details, list org dashboards (`sentry`), list org projects, and look up PagerDuty org integrations (`sentry-pagerduty`).
- `org:write` — `sentry` & `sentry-pagerduty`: update org privacy settings (`scrubIPAddresses`) and create/update custom dashboards (`sentry`), plus POST the PagerDuty service table to `/api/0/organizations/{org}/integrations/{id}/` (`sentry-pagerduty`, since internal integrations cannot be granted `org:integrations` without `org:admin`).
- `alerts:read` — `sentry-pagerduty`: read project error detectors and workflow alerts.
- `alerts:write` — `sentry-pagerduty`: create, update, and delete workflow-engine alerts.

Reconcile behaviour (`SENTRY_TOKEN`, `sntryu_` user token):

- Queries `GET /api/0/organizations/{org}/sentry-apps/` and matches `status == "internal"` (since `SentryAppSerializer` emits `"status": "internal"` rather than `isInternal`).
- Creates the integration via `POST /api/0/sentry-apps/` if missing, or updates scopes via `PUT /api/0/sentry-apps/{slug}/` if they drift.
- Prints the integration slug, reconciled scopes, and UI link:
  `https://sentry.lab.ipv1337.dev/settings/sentry/developer-settings/<slug>/`

One-time human token setup (tokens for API-created internal integrations are created in the Sentry UI):

1. Open the printed UI link and choose **New Token** to create the token.
2. Confirm the new token against `GET /api/0/organizations/{org}/projects/` using `--check` (`SENTRY_CI_TOKEN`):

   ```sh
   read -rs SENTRY_CI_TOKEN && export SENTRY_CI_TOKEN
   bazel run //tools/sentry:ci-integration -- --check
   ```

   It prints `ok` (and any returned scopes) and exits `0`, or prints `denied` and exits non-zero on `401`/`403`.
3. Store the token in the encrypted `sentry-production` environment secret store (hidden prompt) and sync it to GitHub Actions:

   ```sh
   bazel run //tools/sync-env-secrets:set -- sentry-production SENTRY_TOKEN
   bazel run //tools/sync-env-secrets:apply -- sentry-production
   ```

Rotation: follow the same steps — choose **New Token** in the UI, run `--check` with `SENTRY_CI_TOKEN` set to the new token to confirm it, run `set` and `apply` for `sentry-production` `SENTRY_TOKEN`, then delete the old token in the Sentry UI.

## Tests

`bazel test //tools/sentry/...` runs unit tests and subprocess tests against a fake `curl` script with no network access.

## Safety

- `https://` URLs only, so tokens and DSN keys never travel in cleartext.
- curl runs with `-q` (ignores `~/.curlrc`) and without `SENTRY_TOKEN`, `SENTRY_CI_TOKEN`, or `SENTRY_DSN` in its environment; auth headers reach it only through the config on stdin.
- `SENTRY_CURL_BIN` overrides the curl binary (the tests use it for a fake).
  Whatever it names receives the auth header, so only point it at a curl you trust.
