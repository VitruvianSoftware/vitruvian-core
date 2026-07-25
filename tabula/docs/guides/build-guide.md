# Build Guide

This guide explains how to build the Tabula extension for different environments (Development,
Staging, Production).

## Build Architecture

The Tabula extension is a client-side application. It cannot read environment variables (like `.env`
files) at runtime. Instead, configuration is **injected at build time** using Webpack.

We use two primary variables:

- `NODE_ENV`: Controls optimization (minification, logging) and some feature flags.
- `API_URL`: The base URL for the backend API.

## Quick Start

### 1. Local Development (Default)

Connects to local backend (`http://localhost:8080/api/v1`).

```bash
# In root
npm run build --workspace=extension

# OR in extension directory
cd extension
npm run build
```

### 2. Development Branch (Remote Dev)

Connects to the **Development** Cloud Run service.

- **Use case**: Testing with a real deployed backend but "dev" extension code.

```bash
API_URL="https://tabula-api-dev-q7dosy3wiq-uc.a.run.app/api/v1" \
npm run build --workspace=extension
```

### 3. Staging (Release Candidate)

Connects to the **Staging** Cloud Run service.

- **Use case**: Verifying a specific "Freeze" or Release Candidate.
- **Note**: Setting `NODE_ENV=staging` triggers production optimizations (minification).

```bash
NODE_ENV=staging \
API_URL="https://tabula-api-stg-q7dosy3wiq-uc.a.run.app/api/v1" \
npm run build --workspace=extension
```

### 4. Production

Connects to the **Production** Cloud Run service.

```bash
NODE_ENV=production \
API_URL="https://tabula-api-prd-[HASH]-uc.a.run.app/api/v1" \
npm run build --workspace=extension
```

## CI/CD Pipelines

These builds are automated in GitHub Actions:

| Environment     | Workflow                 | Artifact Name                                   |
| :-------------- | :----------------------- | :---------------------------------------------- |
| **Development** | `dev-build.yml` (Manual) | `tabula-extension-dev-[sha].zip`                |
| **Staging**     | `deploy-staging.yml`     | `tabula-extension-rc.zip` (Attached to Release) |
| **Production**  | `release-please.yml`     | `tabula-extension-vX.Y.Z.zip`                   |

## Troubleshooting

### "API_URL is undefined"

If the extension cannot connect, check `chrome://extensions` -> "Inspect views service worker" ->
Console. If you see variable errors, ensure you rebuilt _after_ changing environment variables.
Local changes do not hot-reload environment variables; a full rebuild is required.

### "Mixed Content Error"

If building for Production/Staging (HTTPS) but `API_URL` defaults to `http://localhost`, Chrome will
block the request. Ensure `API_URL` is set correctly during build.
