# GEMINI.md

## Project Overview

This is a full-stack web application designed to inspect OAuth user information from providers like GitHub and Google. The application provides a secure backend for handling the OAuth token exchange process.

The frontend is a React application built with Vite and styled with Tailwind CSS. It allows users to authenticate using OAuth or a Personal Access Token (PAT). The backend is an Express server written in TypeScript that handles the server-side part of the OAuth flow, and now lives entirely under `server/`.

The project is configured for deployment to Google Cloud Run using Docker and Google Cloud Build.

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

### Deployment

Deploy to Cloud Run with:

```bash
npm run deploy
```

The `Dockerfile` copies `server/` rather than individual backend files. Cloud Build uses this Dockerfile to build and deploy.

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
- **Testing:** There are no testing frameworks configured in the project.
- **Commits:** There are no specific commit message conventions enforced.
