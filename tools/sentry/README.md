# sentry

Operational CLI tools for self-hosted Sentry: PagerDuty integration bootstrap (`pagerduty-install`), synthetic alert verification (`send-test-event`), and CI internal integration token provisioning (`ci-token`).

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

Set `SENTRY_TOKEN` in the environment to a **user** auth token (prefix `sntryu_`) with `org:integrations` (or `org:write` / `org:admin`) scope. Export it from Bitwarden item `sentry.lab.ipv1337.dev`, field `SENTRY_TOKEN` (see [infrastructure/pulumi/platform/sentry/README.md](../../infrastructure/pulumi/platform/sentry/README.md)). The token is passed to `curl` only via stdin config (`-K -`) and never placed on the command line or logged; session cookies live in a mode-`0600` file inside a temporary directory deleted on exit.

## Send a synthetic test event (`send-test-event`)

To verify that Sentry → PagerDuty alerting fires end to end, send one synthetic error event to a Sentry project's envelope endpoint:

```sh
bazel run //tools/sentry:send-test-event -- --dsn https://<public_key>@<host>/<project_id> [--level fatal] [--message "Synthetic PagerDuty test"]
```

Each invocation generates a fresh random `event_id` and includes it in `fingerprint`, so Sentry creates a **real new issue** (triggering first-seen alert rules) rather than grouping into an existing issue. Resolve the resulting issue in Sentry afterwards. It sends `User-Agent: sentry.rust/0.35.0` so Cloudflare in front of public ingest accepts the request.

## Mint/rotate CI internal integration token (`ci-token`)

Idempotently ensure self-hosted Sentry has an internal integration (`isInternal=true`, `status: "internal"`) scoped for CI applies of `infrastructure/pulumi/platform/sentry-pagerduty`, mint an API token, and write the raw token to `--out`:

```sh
bazel run //tools/sentry:ci-token -- --name vitruvian-ci --out <path> [--url https://sentry.lab.ipv1337.dev] [--org sentry] [--force] [--revoke-others]
```

Granted scopes (`REQUIRED_SCOPES`): `alerts:read`, `alerts:write`, `org:read`, `org:write`, `project:read`. `org:write` is required because the Pulumi stack POSTs the PagerDuty service table to `/api/0/organizations/{org}/integrations/{id}/` (which accepts `org:write`/`org:admin`/`org:integrations`, and internal integrations cannot be granted `org:integrations` alone).

- **Idempotency & scope reconciliation**: queries `GET /api/0/organizations/{org}/sentry-apps/` and matches `status == "internal"` (since `SentryAppSerializer` emits `"status": "internal"` rather than `isInternal`). Creates the app via `POST /api/0/sentry-apps/` if missing, or updates scopes via `PUT /api/0/sentry-apps/{slug}/` if they drift.
- **Output file safety**: refuses to overwrite an existing `--out` file unless `--force` is passed (checked before any API call). Creates missing parent directories with mode `0700` and writes the raw token with mode `0600` without printing it.
- **Rotation (`--revoke-others`)**: after writing the new token to `--out`, lists `GET /api/0/sentry-apps/{slug}/api-tokens/` and `DELETE`s every other token ID so rotation leaves one live token.
- **Auth (`SENTRY_TOKEN` vs session login)**: sends `SENTRY_TOKEN` (`sntryu_...`) by default. Note that in Sentry `26.10.1`, `/api/0/sentry-apps/{slug}/api-tokens/` enforces `SessionNoAuthTokenAuthentication`, which rejects any `Authorization` header (`403`); when that occurs, set `SENTRY_USER` and `SENTRY_PASSWORD` to authenticate via `/api/0/auth/config/` + `/api/0/auth/login/` using the `0600` session cookie jar instead.

## Tests

`bazel test //tools/sentry/...` runs unit tests and subprocess tests against a fake `curl` script with no network access.

## Safety

- `https://` URLs only, so tokens and DSN keys never travel in cleartext.
- curl runs with `-q` (ignores `~/.curlrc`) and without `SENTRY_TOKEN` or `SENTRY_DSN` in its environment; auth headers reach it only through the config on stdin.
- `SENTRY_CURL_BIN` overrides the curl binary (the tests use it for a fake).
  Whatever it names receives the auth header, so only point it at a curl you trust.
