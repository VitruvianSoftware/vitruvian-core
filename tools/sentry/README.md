# sentry

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

## Tests

`bazel test //tools/sentry/...` runs unit tests and subprocess tests against a fake `curl` script with no network access.

## Safety

- `https://` URLs only, so tokens and DSN keys never travel in cleartext.
- curl runs with `-q` (ignores `~/.curlrc`) and without `SENTRY_TOKEN` or `SENTRY_DSN` in its environment; auth headers reach it only through the config on stdin.
- `SENTRY_CURL_BIN` overrides the curl binary (the tests use it for a fake).
  Whatever it names receives the auth header, so only point it at a curl you trust.
