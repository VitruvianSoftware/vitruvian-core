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

Tests live under `server/__tests__`. They mock external OAuth provider calls using MSW and stub Google Cloud dependencies (Secret Manager and Cloud Logging). If you add new tests that perform network calls, add corresponding MSW handlers or they will be reported as unhandled.

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
