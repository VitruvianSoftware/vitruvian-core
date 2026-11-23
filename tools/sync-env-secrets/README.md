# sync-env-secrets

Manages deploy-time **GitHub Actions secrets that are not in GCP Secret Manager**,
_as code_, from a gitignored local store synced via **Bitwarden**.

This is the sanctioned mechanism for that secret class under
[application-development-principles.md](../../docs/engineering/application-development-principles.md)
**§2.18** (every change ships as code — IaC, GitOps, or a pipeline; never an
imperative one-off) and **§2.4** (secrets never live in git). It replaces ad-hoc
`gh secret set`.

## Why a tool, and why not Pulumi/`repo_config`

Non-secret environment **variables** (project id, region, deploy SA, WIF provider)
_are_ managed as code in `infrastructure/pulumi/platform/repo_config` (`oauthEnvironment`).

The **secrets** _could_ be Pulumi-managed too — `repo_config`'s `dependabotSecrets`
manages `BUILDBUDDY_API_KEY` via a committed `secure:`-encrypted config value that
the Pulumi Cloud backend decrypts in both local and CI applies. We **deliberately**
keep these out of that path:

- Committing the value — **even Pulumi-encrypted** — is a secret in git history
  forever, which **§2.4** forbids. (That `BUILDBUDDY_API_KEY` line is the doc's own
  acknowledged `(target)` debt, not a model to copy.)
- The alternative — reading the value from an env var with no committed config —
  would **flip-flop**: a local apply sets the secret, then the next CI apply,
  lacking the value, **deletes** it from the shared Pulumi state.
- A multiline RSA/JSON machine key is awkward as a Pulumi config secret anyway.

So the raw bytes live in a **gitignored, Bitwarden-backed** store — out of git
entirely — and this idempotent tool `PUT`s them into GitHub (GitHub's secret API
is upsert). Still code, reviewed, and reproducible.

The alternative homes, and when they win:

- **GCP Secret Manager** (preferred) — for app **runtime** secrets the service
  reads via `secretKeyRef`. Managed by the app's own Pulumi stack. Use that when
  the secret never needs to transit CI.
- **This tool** — for **deploy-time** secrets CI itself consumes that aren't in
  GCP SM (a Zitadel machine-user key, a Tailscale on-ramp credential).

## Store layout

Gitignored, one file per secret so arbitrary values (JSON blobs, multiline keys)
round-trip verbatim:

```
tools/sync-env-secrets/secrets/<github-environment>/<SECRET_NAME>   # raw value
```

See [`secrets.example/`](secrets.example/) for the shape (placeholder values).

## Usage

Run it through Bazel (per §2.2 — never invoke the script by hand). The subcommands
are discoverable with `bazel query //tools/sync-env-secrets/...`:

```sh
# Once per machine/session: unlock Bitwarden. Prompts for your master password and
# CACHES the session (0600, ~/.cache/vitruvian-core/bw-session) so the commands
# below — including ones an agent or CI runs headless — work until the vault relocks.
bazel run //tools/sync-env-secrets:unlock

# Pull the store from Bitwarden (new machine), push the store into GitHub as env
# secrets (idempotent), and sync edits back up to Bitwarden:
bazel run //tools/sync-env-secrets:bw-pull
bazel run //tools/sync-env-secrets:apply -- oauth-user-inspector-development
bazel run //tools/sync-env-secrets:bw-push

# When done, drop the cached session and lock the vault:
bazel run //tools/sync-env-secrets:lock
```

## Agent GitHub App keys

A **second** store, same Bitwarden plumbing, different item:
`tools/sync-env-secrets/agent-keys/<agent>.pem` ↔ Bitwarden item
`vitruvian-core/agent-app-keys` (archive `agent-app-keys.tar.gz`).

```sh
bazel run //tools/sync-env-secrets:unlock            # once per session
bazel run //tools/sync-env-secrets:agent-keys-push   # store -> Bitwarden
bazel run //tools/sync-env-secrets:agent-keys-pull   # Bitwarden -> store (new machine)
```

These are the per-agent GitHub App private keys
([agent-github-identities.md](../../docs/guides/agent-github-identities.md)) — the
durable proof of each agent's identity, and unlike an installation token they
**never expire**.

Kept separate from the deploy-env store on purpose: `apply` PUTs the store into
the repository's **GitHub Actions secrets**, which would be both wrong for these
and a far larger blast radius. Only the `agent-keys-*` subcommands repoint the
store, and the script runs one subcommand per invocation, so `apply` cannot reach
them.

An App whose consumer also needs its OAuth client id and secret (Backstage does)
keeps them beside its key as `<name>.creds.json`, written by
`bazel run //tools/agent-app -- convert <code> <name>.pem <name>.creds.json`.
GitHub issues that secret once; the archive is the whole store, so it is backed
up with the key.

`agent-keys-push` refuses to archive any file in the store that is not mode
`600`, rather than silently backing up a world-readable key or secret.

Overrides (env): `REPO` (default `VitruvianSoftware/vitruvian-core`), `BW_ITEM`
(default `vitruvian-core/deploy-env-secrets`), `BW_PASSWORD` (non-interactive
unlock). The store is held in Bitwarden as a single `deploy-env-secrets.tar.gz`
attachment on that item.

> **Note:** `bw-pull` is **additive** — it extracts the archive on top of the local
> store, so a secret you removed from Bitwarden still lingers locally (and `apply`
> would re-push it). To mirror exactly, clear `secrets/<env>/` before pulling.

**Keeping it unlocked for unattended driving.** `:unlock` writes the live vault
session to a `0600` file so headless callers reuse it — a deliberate
convenience/security tradeoff; run `:lock` when you're done. If you prefer an
in-memory agent over an on-disk session, `rbw` is the alternative (not wired here
yet). The `apply` subcommand needs no Bitwarden at all (it only talks to GitHub).

## `oauth-user-inspector-development`

Secrets synced for [oauth-user-inspector
delivery](../../docs/concepts/sdlc.md):

| Secret | What it is |
|---|---|
| `ZITADEL_MACHINE_KEY_JSON` | Zitadel machine-user JWT-profile key the Pulumi zitadel provider authenticates with (the `zitadel-infra` job). |
| `HEADSCALE_CI_AUTHKEY` | Headscale pre-auth key (reusable, ephemeral, `tag:ci`) the Zitadel and Sentry apply workflows join the mesh with, via `.github/actions/homelab-tunnel-setup`. Also in the `-nonproduction`, `-production`, and `sentry-production` environments. Expiry and rotation: [headscale README](../../gitops/argocd/platform/headscale/README.md#ci-pre-auth-key-headscale_ci_authkey). |
| `TS_OAUTH_CLIENT_ID` | Break-glass: the commercial Tailscale OAuth client the CI on-ramp used before Headscale. Nothing reads it today; it is kept on purpose so CI can switch back to commercial Tailscale (see `docs/admin/headscale-tailscale-failover.md`). Do not remove it. |
| `TS_OAUTH_SECRET` | Break-glass, as above (paired with the id). |

Provisioning the machine key (via the in-cluster `iam-admin-pat`) is described in
[`oauth-user-inspector` onboarding](../../apps/web/oauth-user-inspector/infra/identity/);
the Headscale key's minting and rotation are in the
[headscale README](../../gitops/argocd/platform/headscale/README.md#ci-pre-auth-key-headscale_ci_authkey).
Once you hold a value, drop it into `secrets/oauth-user-inspector-<env>/` and run
`bw-push` + `apply`.

## `vitruvian-courier-release`

Secrets of the GitHub Environment that
[`vitruvian-courier-release.yaml`](../../.github/workflows/vitruvian-courier-release.yaml)'s
publishing job binds. The environment itself is declared in
[`repo-config`](../../infrastructure/pulumi/platform/repo-config/vitruvian_courier_release.go):
only `main` and `vitruvian-courier-v*` tags may deploy to it.

| Secret | What it is |
|---|---|
| `COURIER_TELEGRAM_API_ID` | Vitruvian Courier's Telegram app `api_id` (my.telegram.org ▸ API development tools), built into the released app. |
| `COURIER_TELEGRAM_API_HASH` | Its `api_hash`, paired with the id above. |
| `COURIER_KLIPY_API_KEY` | Vitruvian Courier's KLIPY app key (KLIPY partner dashboard), built into the released app for GIF search. Optional: without it the app hides online GIF search. |

The local install reads the same files (the two Telegram ones, and `COURIER_KLIPY_API_KEY`) from `secrets/vitruvian-courier-release/`
(`apps/desktop/vitruvian-courier/app/README.md`). To set them:
`set -- vitruvian-courier-release COURIER_TELEGRAM_API_ID` (and `..._HASH`), then
`apply -- vitruvian-courier-release`.

## `vitruvian-code-release`

Secrets of the GitHub Environment on the public mirror
`VitruvianSoftware/vitruvian-code` that
[`apps/desktop/vitruvian-code/.github/workflows/release.yml`](../../apps/desktop/vitruvian-code/.github/workflows/release.yml)'s
`package` job binds to sign and notarize `Vitruvian Code.app`, the standalone
`vitruvian-code-tool` Mach-O, and the
release `.dmg` disk images. The environment is declared in
[`copybara_sync`](../../infrastructure/pulumi/platform/repo-config/internal/copybara_sync/vitruvian_code_release.go):
only branch `main` may deploy to it.

| Secret | What it is |
|---|---|
| `VITRUVIAN_SIGNING_CERT_P12` | Base64-encoded Apple Developer ID Application `.p12` certificate + private key imported into an ephemeral keychain during packaging. |
| `VITRUVIAN_SIGNING_CERT_PASSWORD` | Passphrase protecting `VITRUVIAN_SIGNING_CERT_P12`. |
| `VITRUVIAN_NOTARY_API_KEY_P8` | App Store Connect API `.p8` private key (PEM or base64) used by `xcrun notarytool`. |
| `VITRUVIAN_NOTARY_KEY_ID` | App Store Connect API Key ID paired with `VITRUVIAN_NOTARY_API_KEY_P8`. |
| `VITRUVIAN_NOTARY_ISSUER_ID` | App Store Connect API Issuer UUID. |

Because this environment lives on the standalone mirror repository rather than
`vitruvian-core`, pass `REPO=VitruvianSoftware/vitruvian-code` when applying
from `secrets/vitruvian-code-release/`:

```sh
REPO=VitruvianSoftware/vitruvian-code bazel run //tools/sync-env-secrets:apply -- vitruvian-code-release
```

## `stripe-sandbox` and `stripe-production`

Secrets of the GitHub Environments that
[`delivery-stripe.yaml`](../../.github/workflows/delivery-stripe.yaml)'s
`stripe-sandbox` and `stripe-production` jobs bind. The environments are
declared in
[`repo-config`](../../infrastructure/pulumi/platform/repo-config/stripe_environments.go):
only `main` may deploy to them, and `stripe-production` also needs a required
reviewer's approval.

| Environment | Secret | What it is |
|---|---|---|
| `stripe-sandbox` | `STRIPE_API_KEY` | A Stripe **sandbox** (test-mode) secret key, ideally a restricted `rk_test_…` key limited to writing Products, Prices, Payment Links, and **Checkout Sessions (`Write`)**. The job refuses any key that does not start `sk_test_` or `rk_test_`. |
| `stripe-production` | `STRIPE_API_KEY` | The **live** account's key, ideally a restricted `rk_live_…` key with the same permissions (including **Checkout Sessions: Write** for the Turnstile checkout Worker). The job refuses any key that does not start `sk_live_` or `rk_live_`. |
| `stripe-sandbox`, `stripe-production` | `CLOUDFLARE_API_TOKEN` | Cloudflare API token with `Account.Turnstile:Edit`, `Account.Workers Scripts:Edit`, `Zone.Workers Routes:Edit`, and `Zone.DNS:Edit` on `vitruviansoftware.dev`. |
| `stripe-sandbox`, `stripe-production` | `CLOUDFLARE_ACCOUNT_ID` | Cloudflare account ID owning the `vitruviansoftware.dev` zone, Workers script, and Turnstile widget. |

To set them: `set -- stripe-sandbox STRIPE_API_KEY` and
`set -- stripe-production STRIPE_API_KEY` (plus `CLOUDFLARE_API_TOKEN` and
`CLOUDFLARE_ACCOUNT_ID` in each environment; each also backs the store up to
Bitwarden), then `apply -- stripe-sandbox` and `apply -- stripe-production`.

## `pagerduty-production`

Secret of the GitHub Environment that
[`delivery-pagerduty.yaml`](../../.github/workflows/delivery-pagerduty.yaml)'s
`pagerduty-production` job binds. The environment is declared in
[`repo-config`](../../infrastructure/pulumi/platform/repo-config/pagerduty_environments.go):
only `main` may deploy to it, with no required reviewer.

| Environment | Secret | What it is |
|---|---|---|
| `pagerduty-production` | `PAGERDUTY_TOKEN` | PagerDuty REST API user token used by `vitruvian-pagerduty` to reconcile escalation policies, services, and integrations. |

To set it: `set -- pagerduty-production PAGERDUTY_TOKEN` (also backs the store
up to Bitwarden), then `apply -- pagerduty-production`.

## `sentry-production`

Secrets of the GitHub Environment that
[`sentry-apply.yaml`](../../.github/workflows/sentry-apply.yaml)'s
`apply` job binds. The environment is declared in
[`repo-config`](../../infrastructure/pulumi/platform/repo-config/sentry_environments.go):
only `main` may deploy to it, with no required reviewer.

| Environment | Secret | What it is |
|---|---|---|
| `sentry-production` | `SENTRY_TOKEN` | Dedicated CI Sentry internal-integration token minted by `bazel run //tools/sentry:ci-token`, used by both `sentry` (`platform/sentry`) and `vitruvian-sentry-pagerduty` (`platform/sentry-pagerduty`) to reconcile org/team/project configuration and PagerDuty workflow alert rules. |
| `sentry-production` | `HEADSCALE_CI_AUTHKEY` | Headscale pre-auth key (reusable, ephemeral, `tag:ci`) used to join the mesh via `.github/actions/homelab-tunnel-setup` — the same value seeded in the `oauth-user-inspector-*` environments. |

To set them: `set -- sentry-production SENTRY_TOKEN` (using the token from
`bazel run //tools/sentry:ci-token`), copy `HEADSCALE_CI_AUTHKEY` from
`secrets/oauth-user-inspector-development/HEADSCALE_CI_AUTHKEY` into
`secrets/sentry-production/HEADSCALE_CI_AUTHKEY` (`bw-push` backs the store up
to Bitwarden), then `apply -- sentry-production`.

## Subdirectories & Boundaries
- [src](./src/README.md): Component package providing implementation for tools/sync-env-secrets/src.

