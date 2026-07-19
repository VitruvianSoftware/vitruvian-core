<div align="center">
<img width="1200" height="475" alt="GHBanner" src="https://github.com/user-attachments/assets/0aa67016-6eaf-458a-adb2-6e31a0763ed6" />
</div>

# OAuth User Inspector

This is a full-stack web application designed to inspect OAuth user information from providers like GitHub and Google. The application provides a secure backend for handling the OAuth token exchange process.

The frontend is a React application built with Vite and styled with Tailwind CSS. It allows users to authenticate using OAuth or a Personal Access Token (PAT). The backend is an Express server written in TypeScript that handles the server-side part of the OAuth flow.

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

> **Custom-domain deploys need a one-time manual step.** The Cloud Run
> DomainMapping behind `oauth-inspector.ipv1337.dev` requires the Site
> Verification API, which is **console-only**: it must be enabled by hand, once,
> on the dev floating project — it CANNOT be enabled via serviceusage/IaC (even
> the project-owner SA gets HTTP 403 PreconditionFailure). Enable it at
> `https://console.cloud.google.com/apis/library/siteverification.googleapis.com?project=prj-d-bu1-oss-floating-648a`.
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
console by hand. See that project's README for the required service-user
credential and how to apply (including importing the existing application so its
Client ID/Secret in Secret Manager stay valid).

## Repository Structure

```
.
├─ frontend/                                       # Frontend source (React + Vite)
│  ├─ App.tsx, index.tsx, index.html, index.css   # Frontend entry and assets
│  ├─ components/                                  # React UI components
│  ├─ utils/                                       # Frontend utilities
│  ├─ types.ts                                     # Frontend type definitions
│  └─ vite.config.ts, tsconfig.json               # Frontend tooling configs
├─ server/                                         # All backend (Express) source
│  ├─ server.ts                                    # Express app
│  ├─ logger.ts                                    # Logging setup
│  ├─ tsconfig.server.json                         # Server TypeScript config
│  ├─ types/express.d.ts                           # Express request typings
│  └─ __tests__/server.test.ts                     # Server tests (Jest + ts-jest)
├─ dist/                                           # Built frontend (vite build)
├─ dist-server/                                    # Compiled backend (tsc)
├─ Dockerfile                                      # Container build
└─ scripts/                                        # Helper scripts (deploy, setup)
```

## Building and Running

### Prerequisites

- Node.js
- npm

### Development

To run the application in development mode, use the following command:

```bash
npm run dev
```

This will start the Vite development server for the frontend and the Express server for the backend (using nodemon for automatic restarts).

### Production

To build the application for production, use the following command:

```bash
npm run build
```

This will create a `dist` directory with the optimized frontend assets and a `dist-server` directory with the compiled backend code.

To start the application in production mode, use the following command:

```bash
npm start
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

The application can be deployed to Google Cloud Run using the provided script:

```bash
npm run deploy
```

This script uses Google Cloud Build to build the Docker image and deploy it to Cloud Run.

## Development Conventions

- **Code Style:** The project uses Prettier for code formatting.
- **Testing:** Backend tests are implemented using Jest and ts-jest.
- **Commits:** There are no specific commit message conventions enforced.
