# oauth-user-inspector — agent guide

> Scoped to `oauth-user-inspector/`. Repo-wide rules live in the root
> [`AGENTS.md`](../AGENTS.md); the developer SOP is [`CONTRIBUTING.md`](../CONTRIBUTING.md),
> which wins on any conflict.

## Project Overview

This is a full-stack web application designed to inspect OAuth user information from providers like GitHub and Google. The application provides a secure backend for handling the OAuth token exchange process.

The frontend is a React application built with Vite and styled with Tailwind CSS. It allows users to authenticate using OAuth or a Personal Access Token (PAT). The backend is an Express server written in TypeScript that handles the server-side part of the OAuth flow, and now lives entirely under `server/`.

The deployed instances run on Google Cloud Run, one per environment, shipped through CI/CD (build once, promote the same image digest through development → nonproduction → production). See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the design and [`docs/OPERATIONS.md`](docs/OPERATIONS.md) for the pipeline, identity, secrets, and runbooks. This file is a quick orientation for coding agents.

## Repository Structure

```
.
├─ frontend/          # React + Vite + Tailwind: App.tsx, components/, utils/,
│                     #   types.ts, fieldDocs.ts, and its own vite/ts/tailwind configs
├─ server/            # Express backend (TypeScript): server.ts, apiEndpoints.server.ts,
│                     #   logger.ts, rateLimit.ts, safeFetch.ts, securityHeaders.ts,
│                     #   oauth-error-guide.ts, types/, __tests__/, tsconfig.server.json
├─ infra/             # Pulumi: per-env Cloud Run app + deploy/runtime identity
├─ deploy/            # Deployment manifests / helpers
├─ docs/              # ARCHITECTURE.md, OPERATIONS.md (design + runbooks)
├─ scripts/           # Helper scripts — see the deployment warning below
├─ dist/              # Built frontend (vite)      — generated
├─ dist-server/       # Compiled backend (tsc)     — generated
└─ Dockerfile         # Container build (copies server/ wholesale)
```

Deliberately coarse: file-level trees here have gone stale before. For anything finer,
read the directory.

## Building and Running

### Prerequisites

- Node.js
- npm

### Development

To run the application in development mode, use:

```bash
npm run dev
```

This starts the Vite dev server and a nodemon process that rebuilds `server/` via `tsc -p server/tsconfig.server.json` and runs `dist-server/server.js`.

### Production

Build everything:

```bash
npm run build
```

Artifacts:

- Frontend: `dist/`
- Backend: `dist-server/` (compiled from `server/`)

Start the compiled server:

```bash
npm start
```

### Testing

Run the tests before proposing changes:

```bash
pnpm test        # jest + ts-jest (server/__tests__ and frontend/__tests__)
```

Outbound HTTP is mocked with a pure-CommonJS fetch mock (`server/__tests__/fetch-mock.ts`); an unregistered network call throws "No handler registered". In CI the same suite runs as `bazel test //oauth-user-inspector:unit_tests`.

### Deployment

The deployed instances run on **Cloud Run**, one per environment, shipped through CI/CD — build once, promote the same image digest through development → nonproduction → production. Do **not** deploy from a workstation. Full pipeline and runbooks: [`docs/OPERATIONS.md`](docs/OPERATIONS.md). The `Dockerfile` copies `server/` rather than individual backend files.

> ⚠️ **`scripts/deploy.sh` (`pnpm run deploy`) is legacy and is NOT how the live instances
> are deployed.** It pushes via Google Cloud Build to a single project, bypassing the
> promotion ladder and the per-environment identities. Running it will not produce the
> deployed state and may diverge from it.

## Notes for Agents/Copilots

- Place all backend code under `server/`. Do not add new backend files at repository root.
- Place all frontend code under `frontend/`. Frontend components, types, utilities, and configs all live there.
- Update `server/tsconfig.server.json` when adding new server entry points or directories.
- Tests for the backend should go in `server/__tests__/` and use Jest + ts-jest.
- Frontend aliases use `@` -> `frontend/` directory; server code should use relative imports within `server/`.
- Dev script assumptions:
  - `npm run dev` expects to find `server/server.ts` and `server/logger.ts` for nodemon watch.
  - Compiled output must be `dist-server/server.js`.
  - Frontend builds to root `dist/` directory from `frontend/` source.

## Development Conventions

- **Code Style:** The project uses Prettier for code formatting.
- **Testing:** Jest + ts-jest (backend in `server/__tests__/`, frontend helpers in `frontend/__tests__/`). Add a test with every behavioral change.
- **Commits:** There are no specific commit message conventions enforced.
