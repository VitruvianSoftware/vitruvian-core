# GitHub App "Vitruvian Desktop" — registration runbook

One GitHub App serves the notch GitHub feature twice: its installation delivers
webhooks to the homelab `github-relay`, and its OAuth flow signs the desktop app
in. Pulumi's GitHub provider cannot create a GitHub App, so this is a one-time
browser step. Design: `docs/superpowers/specs/2026-10-07-notch-github-feature-design.md` §2.2, §4.3.

Prerequisites: PR-2 merged (the relay and `tools/gitops/rotate_github_relay_secrets.sh`
exist), and you are signed in to github.com as a VitruvianSoftware org owner.

## 1. Submit the manifest

```sh
cd docs/github-relay && python3 -m http.server 8321
```

Open <http://localhost:8321/register.html> and click **Create the app on GitHub**.
GitHub shows the manifest's name, permissions and events; confirm with
**Create GitHub App**. It then redirects to this README on github.com with a
`?code=…` query parameter. That code is valid for one hour.

What the manifest sets (`app-manifest.json`):

| Field | Value | Why |
|---|---|---|
| `callback_urls` | `vitruvian://github/callback` | `ASWebAuthenticationSession` captures the redirect; no URL-event handling in the app. |
| `hook_attributes.url` | `https://github-relay.ipv1337.dev/webhook` | The relay's HMAC-verified webhook endpoint. |
| `default_permissions` | `actions`, `checks`, `contents`, `metadata`, `pull_requests` — all **read** | The minimum for check runs, workflow runs, default-branch head and PRs. |
| `default_events` | `check_run`, `check_suite`, `workflow_run`, `pull_request`, `pull_request_review`, `status`, `push` | The seven events the reducer consumes. |
| `public` | `false` | Only VitruvianSoftware can install it. |
| `request_oauth_on_install` | `false` | Sign-in is a separate, explicit "Connect GitHub" click. |

If GitHub rejects the custom-scheme callback URL at this step, stop and report
it: the design assumes GitHub Apps accept custom schemes (GitHub Desktop uses
one), and wren re-confirms this before PR-3.

## 2. Convert the code into credentials

```sh
gh api -X POST /app-manifests/"$CODE"/conversions > /tmp/vitruvian-desktop-app.json
jq '{id, slug, client_id, html_url}' /tmp/vitruvian-desktop-app.json
```

The response also carries `client_secret`, `webhook_secret` and `pem`. Store the
whole file in Bitwarden (item: *GitHub App — Vitruvian Desktop*). The `pem`
(app private key) is not used by the relay today — the design uses
user-to-server tokens only — but it cannot be re-downloaded, so keep it.
Delete `/tmp/vitruvian-desktop-app.json` afterwards.

## 3. Settings the manifest cannot set

In the app's settings page (`html_url` above):

- **Enable Device Flow** — tick it. This is the "Use a code instead" fallback
  when the relay is unreachable.
- **Expire user authorization tokens** — leave **off** (refreshing would need
  the client secret on every refresh, making every refresh depend on the relay).
- Confirm the webhook is **Active** and that **SSL verification** is enabled.

## 4. Install it

Install the app on the **VitruvianSoftware** organisation (all repositories, or
at least `vitruvian-core`) and on your personal account if you want personal
repositories in the watchlist. The desktop app's repository picker only offers
repositories where the app is installed *and* your token can read.

## 5. Feed the secrets to the relay

```sh
bazel run //tools/gitops:rotate_github_relay_secrets -- \
  --client-id "$(jq -r .client_id /tmp/vitruvian-desktop-app.json)" \
  --client-secret-from /dev/stdin \
  --webhook-secret-from <(jq -r .webhook_secret /tmp/vitruvian-desktop-app.json)
```

(Exact flags are those of the rotate tool in PR-2; it seals
`github-relay-webhook` and `github-relay-oauth` without printing values.)
Commit the re-sealed secrets, open a PR, and after ArgoCD syncs run
`bazel run //tools/gitops:github_relay_smoke` — unsigned webhook → 400, signed → 2xx.

## Rotation later

Regenerate the client secret or webhook secret in the app's settings page, then
repeat step 5. Old tokens issued to the desktop app keep working after a
client-secret rotation; a webhook-secret rotation drops events until the
SealedSecret is synced, which the snapshot path on the client absorbs.
