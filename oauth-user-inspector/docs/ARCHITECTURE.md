# Architecture

How OAuth User Inspector is designed and what it's built from. For how it is
built, deployed, and maintained, see [OPERATIONS.md](OPERATIONS.md).

## What it is

A single-page web app that lets a developer sign in to an OAuth/OIDC provider
(or paste a token) and inspect what that identity looks like: the decoded
tokens, the `userinfo`/profile payload, the granted scopes, and the raw provider
API responses. It doubles as a teaching tool for the OAuth **token lifecycle** —
refresh and revoke — across several providers that each implement the standards
a little differently.

It runs as one Cloud Run service per environment. The container serves both the
static frontend and the JSON API from the same origin, so the browser only ever
talks to the app's own domain — never directly to a provider (with narrow,
deliberate exceptions noted below).

## Tech stack

| Layer | Choice | Notes |
| --- | --- | --- |
| Frontend | **React 19** + **Vite 8** + **Tailwind CSS 4** | TypeScript 6, ESM. Built with `vite build` → `dist/`. |
| Backend | **Express 5** on **Node ≥ 22** | TypeScript 6, ESM (`"type": "module"`). Compiled with `tsc` → `dist-server/`. |
| Secrets / logging | `@google-cloud/secret-manager`, `@google-cloud/logging-winston`, `winston` | Runtime creds read from GCP Secret Manager; structured logs to Cloud Logging when running on Cloud Run. |
| Tests | **Jest 30** + **ts-jest** + **supertest** | Node test env. Outbound HTTP mocked with a CommonJS fetch mock. |
| Package manager | **pnpm 10.20** | The monorepo is pnpm-workspace + Bazel. |
| Container | multi-stage **Dockerfile** (`node:22-slim`) | Non-root `nodejs` user, `PORT=8080`, `HEALTHCHECK`, `CMD ["./start.sh"]`. |
| Deploy target | **Cloud Run v2** | Build-once / promote-by-digest, blue-green traffic, per-env. See [OPERATIONS.md](OPERATIONS.md). |

There is **no database** and **no server-side session store**. The server is
stateless: every request carries what it needs, and the only persistent state is
in the browser's `localStorage`/`sessionStorage` (see [Client](#client-react-spa)).

## The big picture

```
                          ┌─────────────────────────────────────────────┐
   Browser (React SPA)    │           Cloud Run service                 │
  ┌───────────────────┐   │   oauth-user-inspector-<env>  (port 8080)   │
  │ LoginScreen        │  │  ┌────────────────────────────────────────┐ │
  │ UserInfoDisplay    │◀─┼──│ Express app (server/server.ts)         │ │
  │ ApiExplorer        │  │  │                                        │ │
  │ TokenDisplay       │──┼─▶│  static:  dist/  (the built SPA)       │ │
  └───────────────────┘   │  │  API:     /api/*                       │ │
        │  same origin     │  │    ├─ securityHeaders (CSP/HSTS/…)     │ │
        │  (no CORS)       │  │    ├─ rateLimit (per-IP tiers)         │ │
        ▼                  │  │    ├─ /api/oauth/{token,refresh,revoke}│ │
   provider redirect       │  │    ├─ /api/oauth-hosted/{init,avail.}  │ │
   (authorize → code)      │  │    └─ /api/explore  (SSRF-safe proxy)  │ │
                           │  └───────────┬────────────────────────────┘ │
                           │              │ safeFetch (pinned egress)     │
                           └──────────────┼───────────────────────────────┘
                                          ▼
                              OAuth / OIDC providers
                    github · google · gitlab · auth0 · zitadel · linkedin
                                          ▲
                           GCP Secret Manager (hosted client id/secret)
```

Two things are worth internalizing before reading further:

1. **Same-origin by design.** The SPA is served by the same Express process that
   exposes the API. There is no CORS middleware because there is no cross-origin
   traffic — when the browser needs a provider response that would otherwise be
   blocked by CORS, it asks the server to fetch it (`POST /api/explore`).
2. **The server holds the secrets, the browser holds the tokens.** Client
   secrets for the "hosted" apps never reach the browser; they live in Secret
   Manager and are used only inside the server's token-exchange handlers. The
   user's *own* access/refresh tokens live only in the browser.

## Two login modes

Every provider can be used in one of two modes, chosen per-login in the UI:

- **BYO (bring-your-own credentials).** The user pastes their own OAuth app's
  Client ID/Secret. The credentials ride along in the browser
  (`sessionStorage`, single-use, cleared right after the code-for-token
  exchange) and are sent to the server only for that one exchange. The user
  registers the app's redirect URI on *their* OAuth application.
- **Hosted ("use our app").** The server uses a pre-registered OAuth application
  whose Client ID/Secret live in GCP Secret Manager under
  `<PROVIDER>_APP_OAUTH_CLIENT_ID` / `_SECRET` (prefixed — see
  [The secret model](#the-secret-model)). The browser never sees these.

A third path, **GitHub Personal Access Token (PAT)**, is handled entirely in the
frontend: the token is used directly from the browser against the GitHub API and
never touches the server.

In every OAuth mode the `redirect_uri` sent to the provider is the app's **own
origin** (`window.location.origin + window.location.pathname`). Providers match
`redirect_uri` byte-for-byte, so each hosted provider application must have the
exact deployed URL (trailing slash included) registered. See the redirect-URI
notes in [OPERATIONS.md](OPERATIONS.md#redirect-uris).

## Client (React SPA)

Source under `frontend/`. `App.tsx` is the root controller — it owns the auth
state machine, dispatches on provider, and handles the OAuth callback by reading
`window.location`.

Key components (`frontend/components/`):

| Component | Responsibility |
| --- | --- |
| `LoginScreen.tsx` | Provider picker; BYO / hosted / GitHub-PAT entry. |
| `ScopeSelector.tsx` | Per-provider OAuth scope picker (`DEFAULT_SCOPES`). |
| `UserInfoDisplay.tsx` | Renders the fetched profile; hosts the token/explorer sub-views. |
| `TokenDisplay.tsx` | Shows access/id/refresh tokens; JWT decode via `jwt-decode`; safe-mode masking. |
| `ApiExplorer.tsx` | Calls a chosen provider endpoint (through `/api/explore`) and renders JSON. |
| `CodeSnippetGenerator.tsx` | Emits `curl`/`node`/`python`/`go` request snippets for an endpoint. |
| `JsonTree.tsx` | Collapsible JSON renderer. |
| `TopMenu.tsx` / `HelpModal.tsx` | Snapshot import/export, safe-mode toggle, logout, help. |
| `EnhancedErrorDisplay.tsx` | Actionable OAuth error banners. |

Notable frontend utilities (`frontend/utils/`):

- **`oauthSession.ts`** — pure (no-network) helpers for the token lifecycle.
  It records `StoredAuthMeta` in `localStorage` (`auth_meta`) so the app can
  *replay* a refresh or revoke later: for BYO it remembers the client id/secret
  and issuer domain; for hosted it just records `isHosted`. `buildRefreshRequest`
  / `buildRevokeRequest` throw or return `null` when BYO credentials are missing
  (→ the app falls back to a local logout).
- **`userinfoRequest.ts`** — decides whether the browser fetches `userinfo`
  directly or must route through `POST /api/explore`. LinkedIn, for example,
  sends no CORS header and *must* be proxied.
- **`apiEndpoints.ts`** — the client-side catalog of explorable endpoints; kept
  in parity with the server-owned table by a test (see
  [Testing](#testing)).

## Server (Express)

All backend code lives under `server/`; `server.ts` (~1700 lines) is the app.
It is exported as an Express `app` and only calls `listen()` when not under Jest,
which lets `supertest` drive it in-process.

### Request pipeline

Middleware, in order:

1. **`securityHeaders()`** (`server/securityHeaders.ts`) — *not* Helmet; a
   hand-rolled middleware setting a strict Content-Security-Policy
   (`default-src 'self'`, `script-src 'self'`, `frame-ancestors 'none'`,
   `object-src 'none'`, …), `Strict-Transport-Security`,
   `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`,
   `X-Frame-Options: DENY`, `Cross-Origin-Opener-Policy: same-origin`.
   `x-powered-by` is disabled; `/api/*` responses are `Cache-Control: no-store`.
2. **`rateLimitMiddleware`** (`server/rateLimit.ts`) — in-memory, per-client-IP,
   tiered: an `api-floor` bucket over all `/api/*` (120 / 5 min), plus tighter
   buckets for `/api/explore` (30/min), the token endpoints (20/min), and the
   hosted endpoints (60/min). Client IP is taken from `CF-Connecting-IP` (the app
   sits behind Cloudflare) falling back to `req.ip` with `trust proxy = 1`.
   Under Jest the limit is effectively disabled.
3. `express.json({ limit: "64kb" })`.
4. Static file serving of `dist/`, then a regex SPA fallback that returns
   `dist/index.html` for any non-API path.

### API endpoints

| Method + path | Purpose |
| --- | --- |
| `POST /api/oauth/token` | OAuth authorization-code → token exchange (hosted uses SM creds; BYO uses body creds). |
| `POST /api/oauth/refresh` | Refresh an access token where the provider supports it. |
| `POST /api/oauth/revoke` | Revoke a token. |
| `POST /api/oauth-hosted/init` | Build the provider `authorize` URL for a hosted login; returns `{ authUrl }`. |
| `GET /api/oauth-hosted/availability` | Reports which providers have hosted creds present in Secret Manager. |
| `GET /api/health` | Liveness: `{ status, uptime, timestamp, node }`. |
| `POST /api/explore` | Same-origin proxy for provider API calls (CORS-avoidance + SSRF containment). |
| `GET /*` | SPA fallback (serves the built React app). |

Providers supported across these handlers: **github, google, gitlab, auth0,
zitadel, linkedin**. Each provider's `token`/`refresh`/`revoke`/`authorize`
endpoints are hardcoded per-provider in `server.ts`; Auth0 and Zitadel also take
an issuer domain (Zitadel defaults to `DEFAULT_ZITADEL_DOMAIN =
"auth.ipv1337.dev"`).

### The secret model

The server reads runtime secrets from **GCP Secret Manager**, never from
plaintext env vars. Two pieces make this multi-tenant-safe:

- **`getSecret(name)`** (exported from `server.ts`) prepends the `SECRET_PREFIX`
  env var to `name`, then reads
  `projects/<GOOGLE_CLOUD_PROJECT>/secrets/<PREFIX><name>/versions/latest`.
  Results are cached in-process for 60 s. If neither `GOOGLE_CLOUD_PROJECT` nor
  `GCP_PROJECT` is set, it throws.
- **`SECRET_PREFIX`** lets several apps co-tenant one GCP project without secret
  name collisions. In production the deployed value is
  `SECRET_PREFIX=OAUTH_USER_INSPECTOR_`, so the provider secret
  `GITHUB_APP_OAUTH_CLIENT_ID` is physically stored as
  `OAUTH_USER_INSPECTOR_GITHUB_APP_OAUTH_CLIENT_ID`. Locally the prefix is empty
  and bare names work.

`getHostedCredentials(provider)` builds the per-provider secret names —
`<PROVIDER>_APP_OAUTH_CLIENT_ID` and `_CLIENT_SECRET` (Auth0 also reads
`_DOMAIN`, Zitadel optionally `_DOMAIN`). `GET /api/oauth-hosted/availability`
uses the presence of these to tell the UI which providers offer a hosted login.

> **Why no `secretKeyRef`.** The Cloud Run service does *not* mount secrets as
> env vars. The server fetches them lazily at request time via the Secret
> Manager API, so a deploy has no build-time dependency on the secrets existing
> yet — the service can roll out first and the creds can land after. The runtime
> service account is granted `secretAccessor` scoped to the
> `OAUTH_USER_INSPECTOR_`-prefixed secrets only (see [OPERATIONS.md](OPERATIONS.md)).

### SSRF containment — the most security-sensitive code

`POST /api/explore` proxies provider API calls on the browser's behalf. Any
"fetch a URL for me" endpoint is an SSRF risk, so this path is fail-closed:

- **The client never supplies a URL.** It supplies `(provider, endpointId)`,
  which the server resolves against `EXPLORE_ENDPOINTS`, a **server-owned**
  allowlist in `server/apiEndpoints.server.ts`. An unknown pair is a hard
  `400`, with no outbound call. Endpoints are either `fixed` (a hardcoded full
  URL) or `issuer` (a fixed path joined to the user's *validated* IdP domain).
- **Egress goes through `safeFetch`** (`server/safeFetch.ts`), the only path for
  user-influenced outbound requests. `resolveAndPin()` resolves the target host
  to all A/AAAA records and requires **every** address to be public unicast — a
  `net.BlockList` denies loopback, RFC1918, CGNAT `100.64.0.0/10` (Tailscale),
  link-local incl. the cloud metadata IP `169.254.169.254`, IPv4-mapped IPv6,
  ULA, and IANA special ranges. It then connects to the vetted **IP literal**
  (passing `servername` for TLS) so DNS cannot be re-resolved to a private
  address between check and connect (no DNS-rebind TOCTOU). Redirects are never
  followed; body size and time are bounded. Upstream failures collapse to a
  generic `502` so the endpoint can't be used as an SSRF recon oracle.

A parity test (`explore-endpoints-parity.test.ts`) asserts the client catalog
and the server allowlist stay in sync, and dedicated `ssrf.test.ts` /
`safefetch-*` tests guard the egress rules.

## Runtime configuration

Environment variables the server reads (all optional unless noted):

| Var | Default | Meaning |
| --- | --- | --- |
| `PORT` | `8080` | Listen port (Docker/Cloud Run set it). |
| `SECRET_PREFIX` | `""` | Secret-name namespace; prod = `OAUTH_USER_INSPECTOR_`. |
| `GOOGLE_CLOUD_PROJECT` / `GCP_PROJECT` | — | **Required for Secret Manager** (one of the two). |
| `NODE_ENV` | `development` | Docker sets `production`. |
| `LOG_LEVEL` | `info` | winston level. |
| `K_SERVICE`, `K_REVISION`, `GOOGLE_CLOUD_REGION`, … | — | Cloud Run injects these; presence switches logging to Cloud Logging. |
| `JEST_WORKER_ID` | — | Set by Jest; skips `listen()` and relaxes rate limits. |

Provider OAuth credentials are **not** env vars — they are Secret Manager
entries (see [The secret model](#the-secret-model)).

## Container

The `Dockerfile` is multi-stage:

- **build stage** (`node:${NODE_VERSION}-slim`, default 22): `corepack enable`,
  `pnpm install`, `pnpm build` (frontend via Vite → `dist/`, server via `tsc` →
  `dist-server/`). A `sed` neutralizes the monorepo's pnpm `catalog:` version
  refs so the image builds standalone.
- **runtime stage**: `NODE_ENV=production`, `PORT=8080`, prod-only deps, copies
  `dist/` + `dist-server/` + `start.sh`, runs as non-root `nodejs` (uid 1001),
  `EXPOSE 8080`, a curl `HEALTHCHECK` against `/`, and `CMD ["./start.sh"]`.

`start.sh` prints a short diagnostic banner, asserts the build outputs exist
(fails fast with an `ls` if not), then `exec node dist-server/server.js`.

## Testing

- Config: `jest.config.cjs` — `ts-jest` preset, `node` test env, matches
  `**/__tests__/**/*.test.ts`.
- Server suites (`server/__tests__/`): the main handler suite (`server.test.ts`)
  plus focused suites for SSRF (`ssrf.test.ts`), rate-limit/hardening
  (`hardening.test.ts`), the secret prefix (`secret-prefix.test.ts`), the
  explore-endpoint parity check, dependency consistency, and the OAuth error
  guide. HTTP is asserted with `supertest` against the exported `app`.
- **Fetch mock:** outbound provider calls are intercepted by a pure-CommonJS
  mock (`server/__tests__/fetch-mock.ts`) — msw was dropped because its ESM-only
  build broke under ts-jest in the hermetic Bazel sandbox. A test that makes an
  unregistered network call throws "No handler registered"; register handlers
  with `fetchMock.register()` / `.use()`.
- Frontend helpers are unit-tested under `frontend/__tests__/`
  (`oauthSession.test.ts`, `userinfoRequest.test.ts`) in the same Jest env.
- Run with `pnpm test` (or `npm test`) locally, or
  `bazel test //oauth-user-inspector:unit_tests` in CI.

## App metadata

- `catalog-info.yaml` — a Backstage `Component` (`type: service`,
  `system: vitruvian-core`, owner `oauth-user-inspector-team`). It carries the
  deploy-workflow and mirror annotations and is consumed by `tools/conformance`
  (the declared owner must match `.github/CODEOWNERS`).
- `deploy/chart/` — a Helm chart published to
  `oci://ghcr.io/vitruviansoftware/charts/oauth-user-inspector`. It is an
  **alternate** Kubernetes/ArgoCD delivery path for the same image; the live
  deployment of this instance is Cloud Run via the Pulumi stacks and the
  `oauth-user-inspector-deploy.yaml` pipeline (see [OPERATIONS.md](OPERATIONS.md)).
  The chart exists so the image can also be run on a cluster if desired.
