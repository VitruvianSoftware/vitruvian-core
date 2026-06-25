# GEMINI.md

## Project Overview

This is a full-stack web application designed to inspect OAuth user information from providers like GitHub and Google. The application provides a secure backend for handling the OAuth token exchange process.

The frontend is a React application built with Vite and styled with Tailwind CSS. It allows users to authenticate using OAuth or a Personal Access Token (PAT). The backend is an Express server written in TypeScript that handles the server-side part of the OAuth flow, and now lives entirely under `server/`.

## Repository Structure

```
.
├─ frontend/                                     # All frontend source
│  ├─ App.tsx, index.tsx, index.html, index.css # Frontend entry and assets
│  ├─ components/                                # React components
│  ├─ utils/                                     # Frontend utilities
│  ├─ types.ts, fieldDocs.ts                    # Type definitions and field docs
│  ├─ vite.config.ts, tsconfig.json             # Frontend build configs
│  └─ tailwind.config.js, postcss.config.js     # Styling configs
├─ server/                                       # All backend (Express) source
│  ├─ server.ts                                  # Express app
│  ├─ logger.ts                                  # Logging setup
│  ├─ tsconfig.server.json                       # Server TypeScript config
│  ├─ types/express.d.ts                         # Express request typings
│  └─ __tests__/server.test.ts                   # Backend tests
├─ dist/                                         # Built frontend (vite)
├─ dist-server/                                  # Compiled backend (tsc)
├─ Dockerfile                                    # Container build
├─ scripts/                                      # Helper scripts (deploy, setup)
└─ tsconfig.json                                 # Root TypeScript config with project refs
```

## Building and Running

### Prerequisites

- Node.js
- npm

### Development

Run both frontend and backend in watch mode:

```bash
npm run dev
```

This starts Vite for the frontend and nodemon for the backend. Nodemon rebuilds via `tsc -p server/tsconfig.server.json` and runs `dist-server/server.js`.

### Production

Build everything:

```bash
npm run build
```

This creates a `dist` directory with the optimized frontend assets and a `dist-server` directory with the compiled backend code.

Start the compiled server:

```bash
npm start
```

### Testing

Run backend tests (Jest + ts-jest):

```bash
npm test
```

Tests are located under `server/__tests__`. External calls are mocked using MSW; Google Cloud dependencies (Secret Manager, Cloud Logging) are stubbed. If you add tests that perform network calls, add MSW handlers.

### Deployment

Deploy to Google Cloud Run using the provided script:

```bash
npm run deploy
```

This uses Google Cloud Build to build the Docker image (the Dockerfile copies `server/`) and deploy to Cloud Run.

## Development Conventions

- **Code Style:** The project uses Prettier for code formatting.
- **Testing:** Backend tests are implemented using Jest and ts-jest under `server/__tests__`.
- **Commits:** There are no specific commit message conventions enforced.
