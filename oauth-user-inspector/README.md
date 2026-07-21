<div align="center">
<img width="1200" height="475" alt="GHBanner" src="https://github.com/user-attachments/assets/0aa67016-6eaf-458a-adb2-6e31a0763ed6" />
</div>

# OAuth User Inspector

This is a full-stack web application designed to inspect OAuth user information from providers like GitHub and Google. The application provides a secure backend for handling the OAuth token exchange process.

The frontend is a React application built with Vite and styled with Tailwind CSS. It allows users to authenticate using OAuth or a Personal Access Token (PAT). The backend is an Express server written in TypeScript that handles the server-side part of the OAuth flow.

## Documentation

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — how it's designed and what
  it's built from: the client/server split, the two login modes, the secret
  model, SSRF containment, and the full tech stack.
- **[docs/OPERATIONS.md](docs/OPERATIONS.md)** — how it's built, deployed, and
  maintained: the multi-env pipeline, keyless identity, secrets, custom domains,
  Zitadel hosted-login, and step-by-step runbooks.

## Tech stack at a glance

React 19 + Vite 8 + Tailwind 4 (frontend) · Express 5 on Node ≥ 22, TypeScript 6
(backend) · pnpm 10 + Bazel · Jest 30 · Docker → **Cloud Run** (built once,
promoted by digest across dev → nonproduction → production) · Pulumi (Go) + GitHub
Actions with Workload Identity Federation · GCP Secret Manager for runtime creds.
No database — the server is stateless. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Features

### OAuth Token Lifecycle Management

This application demonstrates OAuth token lifecycle best practices including:

- **🔄 Token Refresh**: Automatically refresh access tokens using refresh tokens when available
- **🚫 Token Revocation**: Securely revoke access tokens for immediate invalidation
- **📊 Token Analysis**: Display token metadata including scopes, expiration, and type
- **🔐 Security Education**: Learn about proper token handling and security practices

#### Provider Support

| Provider | Token Refresh | Token Revocation | Notes                                     |
| -------- | ------------- | ---------------- | ----------------------------------------- |
| Google   | ✅            | ✅               | Full OAuth 2.0 support                    |
| GitLab   | ✅            | ✅               | Enterprise-ready features                 |
| Auth0    | ✅            | ✅               | Identity platform support                 |
| LinkedIn | ✅            | ⚠️               | Limited revocation API                    |
| GitHub   | ❌            | ✅               | OAuth Apps don't support refresh tokens\* |

\*Note: GitHub Apps (not OAuth Apps) do support refresh tokens, but this demo uses OAuth Apps for simplicity.

### Educational Value

- **Developer Learning**: Understand OAuth 2.0 token flows and security practices
- **API Integration**: See real-world examples of token refresh and revocation
- **Security Best Practices**: Learn about token lifecycle management
- **Provider Differences**: Compare how different OAuth providers implement standards

## Hosted OAuth & redirect URIs

The app supports two login modes per provider:

- **BYO (bring-your-own credentials):** you paste your own Client ID/Secret. You
  register the redirect URI shown in the UI on **your** OAuth application.
- **Hosted ("use our app"):** the server uses a pre-configured OAuth application
  whose Client ID/Secret live in GCP Secret Manager (`<PROVIDER>_APP_OAUTH_*`).

In **both** modes the redirect URI sent to the provider is the app's own origin,
`window.location.origin + window.location.pathname`. For the deployed instance
that is exactly:

```
https://oauth-inspector.ipv1337.dev/
```

> **Custom-domain deploys need a one-time manual step per environment.** Each
> env's Cloud Run DomainMapping requires that env's deploy SA to self-verify
> the domain via the Site Verification API (ownership there is per-caller —
> the deploy pipeline does this automatically), and that API is
> **console-only**: it must be enabled by hand, once, on EVERY oss floating
> project — it CANNOT be enabled via serviceusage/IaC (even the project-owner
> SA gets HTTP 403 PreconditionFailure). URL pattern:
> `https://console.cloud.google.com/apis/library/siteverification.googleapis.com?project=<PROJECT_ID>`.
> Status: dev (`prj-d-bu1-oss-floating-648a`) is done; still to enable:
>
> - <https://console.cloud.google.com/apis/library/siteverification.googleapis.com?project=prj-n-bu1-oss-floating-630b>
> - <https://console.cloud.google.com/apis/library/siteverification.googleapis.com?project=prj-p-bu1-oss-floating-16e0>
>
> Details: [`tools/ci/ensure-site-verification.sh`](../tools/ci/ensure-site-verification.sh).

OAuth providers match `redirect_uri` **exactly** (the trailing slash is
significant), so every hosted provider application must have that precise string
registered in its allowed redirect URIs. If it doesn't, the provider rejects the
authorize request before the user ever returns to the app — e.g. Zitadel returns
`invalid_request` with _"The requested redirect_uri is missing in the client
configuration."_

> The authorize URL percent-encodes `redirect_uri`, but providers compare the
> decoded value — so register the **decoded** form above (with the trailing
> slash), not a percent-encoded one.

### Zitadel (self-hosted) — managed as code

The Zitadel **instance** is GitOps-managed
(`gitops/argocd/platform/zitadel/`). The hosted oauth-user-inspector **OAuth
application** and its redirect URIs are managed as code (Pulumi) under
[`infrastructure/pulumi/platform/zitadel-apps/`](../infrastructure/pulumi/platform/zitadel-apps/) —
add or change a redirect URI there and re-apply rather than editing the Zitadel
console by hand. The stack **creates and owns** the OIDC client (it is never
imported — this provider's import plans a destructive replace that would delete
the live client) and syncs its Client ID/Secret into each environment's GCP
Secret Manager. See [docs/OPERATIONS.md](docs/OPERATIONS.md#zitadel-hosted-login)
for the per-env clients, redirect URIs, and how the CI apply reaches Zitadel over
the tailnet.

## Repository Structure

```
.
├─ frontend/                                       # Frontend source (React + Vite)
│  ├─ App.tsx, index.tsx, index.html, index.css   # Frontend entry and assets
│  ├─ components/                                  # React UI components
│  ├─ utils/                                       # Frontend utilities (oauthSession, apiEndpoints, …)
│  ├─ types.ts                                     # Frontend type definitions
│  └─ vite.config.ts, tsconfig.json               # Frontend tooling configs
├─ server/                                         # All backend (Express) source
│  ├─ server.ts                                    # Express app
│  ├─ apiEndpoints.server.ts                       # Server-owned explore allowlist (SSRF)
│  ├─ safeFetch.ts                                 # Pinned, SSRF-safe outbound fetch
│  ├─ securityHeaders.ts, rateLimit.ts             # Security middleware
│  ├─ logger.ts                                    # Logging setup
│  └─ __tests__/                                   # Server tests (Jest + ts-jest)
├─ infra/                                          # Per-app Pulumi (Go) infrastructure
│  ├─ app/                                         # Cloud Run service + custom domain (per env)
│  └─ identity/                                    # Deploy/runtime service accounts + WIF (per env)
├─ deploy/chart/                                   # Helm chart (alternate Kubernetes delivery)
├─ docs/                                           # ARCHITECTURE.md, OPERATIONS.md
├─ dist/                                           # Built frontend (vite build)
├─ dist-server/                                    # Compiled backend (tsc)
├─ Dockerfile                                      # Container build
└─ scripts/                                        # Helper scripts (setup, legacy deploy)
```

> The shared **build** stack (Artifact Registry + build service account) lives
> outside this directory at
> [`infrastructure/pulumi/apps/oauth-user-inspector-build/`](../infrastructure/pulumi/apps/oauth-user-inspector-build/)
> because it is a single cross-environment resource, not per-env. See
> [docs/OPERATIONS.md](docs/OPERATIONS.md#the-moving-parts).

## Building and Running

### Prerequisites

- Node.js ≥ 22
- pnpm 10 (`corepack enable` will provide it) — the repo also builds under Bazel

### Development

To run the application in development mode, use the following command:

```bash
pnpm dev
```

This will start the Vite development server for the frontend and the Express server for the backend (using nodemon for automatic restarts). The BYO-credential and GitHub-PAT login paths work with no GCP access; to exercise the hosted-login paths, set `GOOGLE_CLOUD_PROJECT` and use Application Default Credentials against Secret Manager (see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#the-secret-model)).

### Production

To build the application for production, use the following command:

```bash
pnpm build
```

This will create a `dist` directory with the optimized frontend assets and a `dist-server` directory with the compiled backend code.

To start the application in production mode, use the following command:

```bash
pnpm start
```

### Testing

The project uses Jest with ts-jest for backend API tests. To run the test suite:

```bash
npm test
```

Server tests live under `server/__tests__` and drive the real Express app via `supertest`. Outbound OAuth provider calls (the server uses `node-fetch`) are intercepted by a small CommonJS fetch mock (`server/__tests__/fetch-mock.ts`); Google Cloud dependencies (Secret Manager and Cloud Logging) are stubbed. If you add a test that performs a network call, register a handler via `fetchMock.register()` / `fetchMock.use()` or the request will throw "No handler registered". Pure frontend helpers (e.g. `frontend/utils/oauthSession.ts`) are unit-tested under `frontend/__tests__` and run in the same Jest (node) environment.

If Jest ever appears to hang, you can diagnose open handles with:

```bash
npx jest --detectOpenHandles
```

### Environment Variables in Tests

During tests a dummy `GOOGLE_CLOUD_PROJECT` is set automatically. Real Google Cloud access is not performed; logging is mocked. When running the server locally (non-test), set any required secrets or use Google Secret Manager in your Cloud environment.

### Deployment

The live deployment is **Cloud Run**, one service per environment, delivered
entirely through CI/CD — there is no sanctioned local deploy. On a merge to
`main`, the [`oauth-user-inspector-deploy.yaml`](../.github/workflows/oauth-user-inspector-deploy.yaml)
workflow builds the image **once**, pushes it to the shared Artifact Registry,
and promotes the **same digest** through **development → nonproduction →
production** (nonproduction and production are reviewer-gated), each with a
blue-green candidate-then-promote traffic shift and a smoke check. Authentication
is keyless (Workload Identity Federation); runtime secrets come from GCP Secret
Manager.

See **[docs/OPERATIONS.md](docs/OPERATIONS.md)** for the full pipeline, identity
and secret model, custom domains, and runbooks (deploy, promote, roll back,
rotate a secret, add a provider).

> The legacy `scripts/deploy.sh` (`pnpm run deploy`) is the old single-project
> Cloud Build path and is **not** how the deployed instances are shipped.

## Development Conventions

- **Code Style:** The project uses Prettier for code formatting.
- **Testing:** Backend and frontend helpers are tested with Jest + ts-jest (`pnpm test`, or `bazel test //oauth-user-inspector:unit_tests`). See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#testing).
- **Commits:** Conventional-commit prefixes are used across the monorepo (e.g. `feat(oauth-user-inspector): …`), enforced by the merge queue.
