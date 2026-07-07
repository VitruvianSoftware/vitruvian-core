Can# Development Guide

This guide will help you set up your local development environment for Tabula.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
- [Project Structure](#project-structure)
- [Running Locally](#running-locally)
- [Development Workflows](#development-workflows)
- [Code Organization](#code-organization)
- [Debugging](#debugging)
- [Common Tasks](#common-tasks)
- [Troubleshooting](#troubleshooting)

## Prerequisites

Before you begin, ensure you have the following installed:

- **Node.js** 22+
- **Bazel** (via `bazelisk`)
- **pnpm** (via Corepack or globally installed)
- **Docker** & **Tailscale** (for local K3s access)
- **Git**
- **gcloud CLI**

### Optional but Recommended

- **PostgreSQL client** (psql) for database debugging
- **Redis client** (redis-cli) for cache debugging

## Initial Setup

### 1. Clone the Repository

```bash
git clone https://github.com/VitruvianSoftware/vitruvian-core.git
cd vitruvian-core
```

### 2. Set Up the Bazel Environment

The monorepo uses Bazel to guarantee reproducible builds and testing.

```bash
bazel run //tools:bazel_env
direnv allow
```

This ensures you're using the correct pinned version of Node, Go, and other toolchains.

### 3. Connect to the K3s Homelab

We use a production-ready K3s cluster over Tailscale instead of raw `docker-compose`. Ensure your Tailscale daemon is running and authorized with the `tag:claude-cloud` tag.

The cluster provides PostgreSQL, Redis, and Zitadel (IdP) natively.

### 4. Setup Workload Identity Federation (GCP)

To deploy to Google Cloud Run or interact with GCP resources, you don't need a static service account key. Pulumi handles Workload Identity Federation automatically.

Ensure your `infrastructure/gcp-identities.tsv` maps your environment to the correct account:

```bash
export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token --account=your.email@gmail.com)"
```

### 5. Configure Zitadel Authentication

Tabula uses Zitadel (deployed in the K3s homelab) for SSO authentication.

1. The API and frontend will automatically fetch the OIDC discovery endpoints from `auth.ipv1337.dev`.
2. To apply new redirect URIs or create new clients, update the Pulumi stack in `infrastructure/pulumi/platform/zitadel-apps/` and run `pulumi up`.

## Project Structure

```
tabula/
├── api/                      # Backend API
│   ├── src/
│   │   ├── routes/          # API routes/controllers
│   │   ├── services/        # Business logic
│   │   ├── middleware/      # Express/Fastify middleware
│   │   ├── utils/           # Utility functions
│   │   ├── types/           # TypeScript type definitions
│   │   └── app.ts           # Application entry point
│   ├── tests/               # API tests
│   ├── prisma/              # Database schema and migrations
│   ├── jest.config.js       # Jest configuration
│   ├── tsconfig.json        # TypeScript configuration
│   └── package.json         # API dependencies
│
├── extension/               # Browser extension
│   ├── src/
│   │   ├── background/      # Service worker
│   │   ├── popup/           # Popup UI
│   │   ├── content/         # Content scripts
│   │   ├── components/      # React components
│   │   └── manifest.json    # Extension manifest
│   ├── tests/               # Extension tests
│   └── package.json         # Extension dependencies
│
├── web/                     # Web dashboard (Phase 2)
│   └── src/
│
├── docs/                    # Documentation
│   ├── architecture/        # Architecture docs
│   ├── getting-started/     # Setup and development guides
│   ├── guides/              # How-to guides
│   ├── product/             # Product docs
│   └── reference/           # Reference docs
│
├── .github/                 # GitHub configuration
│   └── workflows/           # CI/CD pipelines
│
├── package.json             # Root workspace configuration
├── docker-compose.yml       # Local development services
└── README.md                # Project overview
```

## Running Locally

### Start the API Server

```bash
ibazel run //tabula/api:dev
```

The API will be available at http://localhost:8080

### Build the Extension

```bash
ibazel run //tabula/extension:dev
```

This watches for changes and rebuilds automatically.

### Load Extension in Chrome

1. Open Chrome and navigate to `chrome://extensions/`
2. Enable "Developer mode" (toggle in top right)
3. Click "Load unpacked"
4. Select the `bazel-bin/tabula/extension/...` directory
5. The extension should now appear in your browser

## Development Workflows

### Overview

```mermaid
gitGraph
   commit
   commit
   branch feature/shiny-new-thing
   checkout feature/shiny-new-thing
   commit
   commit

    %% Preview Environment Flow
    commit id: "Open PR" type: HIGHLIGHT
    commit id: "infra preview up"
    commit id: "infra preview down"

   checkout main
   merge feature/shiny-new-thing
   commit id: "Merge PR" type: HIGHLIGHT

   %% Deployment Flow
   commit id: "Deploy Dev"
   commit id: "Auto-Migration"

   %% Release
   commit id: "Release" tag: "v1.0.0"
   commit id: "Deploy Prod" type: HIGHLIGHT
```

### Making Changes

1. Create a new branch:

   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes

3. Run tests:

   ```bash
   npm test
   ```

4. Lint and format:

   ```bash
   npm run lint:fix
   npm run format
   ```

5. Commit following [Conventional Commits](https://www.conventionalcommits.org/):

   ```bash
   git commit -m "feat: add new feature"
   # or
   git commit -m "fix: resolve issue with ..."
   ```

6. Push and create Pull Request:
   ```bash
   git push origin feature/your-feature-name
   ```

### 7. Preview Environments

You can create ephemeral preview environments for Pull Requests.

```bash
# Create preview (Cloud Run via Pulumi)
pulumi stack select pr-<pr-id> --create
pulumi up

# Destroy preview
pulumi destroy
pulumi stack rm pr-<pr-id>
```

### Running Tests

```bash
# Run all tests
bazel test //...

# Run tests in watch mode for a target
ibazel test //tabula/api/...

# Run tests with coverage
bazel coverage //tabula/...

# Run specific test file
bazel test //tabula/api/... --test_filter="AuthService"

# Run E2E tests
bazel test //tabula/extension:e2e
```

### Database Operations

```bash
# Create a new migration
npx prisma migrate dev --name add_user_preferences

# Reset database (WARNING: deletes all data)
npx prisma migrate reset

# Open Prisma Studio (database GUI)
npx prisma studio

# Generate Prisma client after schema changes
npx prisma generate
```

### Linting and Formatting

```bash
# Lint all code via Aspect CLI
aspect lint //...

# Format all code
bazel run //:tidy
```

### Type Checking

```bash
# Check types across all workspaces
npm run typecheck

# Check types for specific workspace
npm run typecheck --workspace=api
```

## Code Organization

### API Code Organization

- **routes/**: HTTP route handlers (thin controllers)
- **services/**: Business logic (core functionality)
- **middleware/**: Request processing (auth, validation, logging)
- **utils/**: Shared utility functions
- **types/**: TypeScript type definitions

**Example structure:**

```typescript
// routes/workspace.routes.ts
export function workspaceRoutes(app: FastifyInstance) {
  app.get('/workspaces', getWorkspaces);
  app.post('/workspaces', createWorkspace);
}

// services/workspace.service.ts
export class WorkspaceService {
  async createWorkspace(userId: string, data: CreateWorkspaceDTO) {
    // Business logic here
  }
}
```

### Extension Code Organization

- **background/**: Service worker for background tasks
- **popup/**: React components for popup UI
- **content/**: Scripts injected into web pages
- **components/**: Reusable React components

## Debugging

### API Debugging

**VS Code Launch Configuration** (`.vscode/launch.json`):

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "node",
      "request": "launch",
      "name": "Debug API",
      "runtimeExecutable": "npm",
      "runtimeArgs": ["run", "dev", "--workspace=api"],
      "skipFiles": ["<node_internals>/**"]
    }
  ]
}
```

**Using Node Inspector:**

```bash
node --inspect-brk api/dist/app.js
# Then open chrome://inspect in Chrome
```

### Extension Debugging

1. Open Chrome DevTools on extension popup
2. Use `console.log()` in background script (visible in extension service worker)
3. Use React DevTools for component debugging

### Database Debugging

```bash
# Connect to local database
psql -h localhost -U tabula -d tabula_dev

# View tables
\dt

# Query data
SELECT * FROM users;

# View query logs (in Prisma)
# Set DEBUG=prisma:query in environment
```

## Common Tasks

### Adding a New API Endpoint

1. Define route in `api/src/routes/`
2. Implement service logic in `api/src/services/`
3. Add validation schema using Zod
4. Write tests in `api/tests/integration/`
5. Update OpenAPI spec in `api/openapi.yaml`

### Adding a New Database Table

1. Update `tabula/api/prisma/schema.prisma`
2. Run `npx prisma migrate dev --name add_table_name`
3. Run `npx prisma generate` to update types
4. Write tests for new functionality

### Adding a New Extension Feature

1. Implement in appropriate directory (background, popup, content)
2. Update manifest.json if new permissions needed
3. Write tests in `extension/tests/`
4. Test in actual browser

### Updating Dependencies

```bash
# Check for outdated packages
npm outdated

# Update dependencies
npm update

# Update to latest versions (careful!)
npx npm-check-updates -u
npm install
```

## Troubleshooting

### Database Connection Issues

```bash
# Check if PostgreSQL is running on the homelab tailnet
ping postgres.ipv1337.dev

# Or use kubectl to check the pod
kubectl get pods -n tabula-dev
```

### Build Errors

```bash
# Clear build cache
rm -rf api/dist extension/dist

# Clear node_modules and reinstall
rm -rf node_modules api/node_modules extension/node_modules
npm install
```

### Type Errors

```bash
# Regenerate Prisma client
npx prisma generate
```

### Port Already in Use

```bash
# Find process using port 8080
lsof -i :8080

# Kill process
kill -9 <PID>
```

### Extension Not Loading

1. Check for errors in `chrome://extensions/`
2. Verify build completed: `ls extension/dist/`
3. Rebuild: `npm run build --workspace=extension`
4. Hard reload: Remove and re-add extension

## Getting Help

- **Documentation:** Check `/docs` directory
- **Issues:** [GitHub Issues](https://github.com/BlueCentre/tabula/issues)
- **Discussions:** [GitHub Discussions](https://github.com/BlueCentre/tabula/discussions)
- **Code Review:** Ask in pull requests

## Next Steps

- Read [Testing Guide](../guides/testing.md) for testing guidelines
- Review [Architecture Overview](../architecture/overview.md) for system design
- Check [CONTRIBUTING.md](../../CONTRIBUTING.md) for contribution guidelines

---

**Happy coding! 🚀**
