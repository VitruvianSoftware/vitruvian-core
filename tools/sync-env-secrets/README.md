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
_are_ managed as code in `infrastructure/pulumi/repo_config` (`oauthEnvironment`).

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

```sh
# One-time / new machine: pull the store from Bitwarden (needs an unlocked vault)
export BW_SESSION="$(bw unlock --raw)"
./sync-env-secrets.sh bw-pull

# Push the local store into GitHub as environment secrets (idempotent)
./sync-env-secrets.sh apply oauth-user-inspector-development

# After editing a secret locally, sync the store back up to Bitwarden
./sync-env-secrets.sh bw-push
```

Overrides: `REPO` (default `VitruvianSoftware/vitruvian-core`), `BW_ITEM` (default
`vitruvian-core/deploy-env-secrets`). The store is stored in Bitwarden as a single
`deploy-env-secrets.tar.gz` attachment on that item.

## `oauth-user-inspector-development`

Secrets synced for the [oauth-user-inspector
deploy](../../.github/workflows/oauth-user-inspector-deploy.yaml):

| Secret | What it is |
|---|---|
| `ZITADEL_MACHINE_KEY_JSON` | Zitadel machine-user JWT-profile key the Pulumi zitadel provider authenticates with (the `zitadel-infra` job). |
| `TS_OAUTH_CLIENT_ID` | Tailscale OAuth client id for the CI tailnet on-ramp (`tailscale/github-action`). |
| `TS_OAUTH_SECRET` | Tailscale OAuth client secret (paired with the id above). |

Provisioning these (machine key via the in-cluster `iam-admin-pat`; the Tailscale
OAuth client in the admin console) is described in
[`oauth-user-inspector` onboarding](../../infrastructure/pulumi/oauth-user-inspector-deploy-identity/);
once you hold the values, drop each into `secrets/oauth-user-inspector-development/`
and run `apply` + `bw-push`.
