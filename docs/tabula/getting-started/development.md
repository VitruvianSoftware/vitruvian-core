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

- **Node.js** 18+ ([Download](https://nodejs.org/))
- **npm** 9+ (comes with Node.js)
- **Docker** ([Download](https://www.docker.com/get-started))
- **Git** ([Download](https://git-scm.com/downloads))
- **VS Code** (recommended) or your preferred editor

### Optional but Recommended

- **PostgreSQL client** (psql) for database debugging
- **Redis client** (redis-cli) for cache debugging
- **Postman** or **Insomnia** for API testing

## Initial Setup

### 1. Clone the Repository

```bash
git clone https://github.com/BlueCentre/tabula.git
cd tabula
```

### 2. Install Dependencies

```bash
npm install
```

This will install dependencies for all workspaces (api, extension, web, cli).

### 3. Set up TabCLI (Recommended)

To run `tabcli` commands directly from your shell, build and link the CLI:

```bash
# Build the CLI
npm run build --workspace=cli

# Link globally
cd cli && npm link && cd ..
```

Now you can run `tabcli` commands from anywhere.

### 4. Initialize TabCLI Configuration

```bash
tabcli init
```

This will prompt you for configuration values and create `.tabula/config.json`.

> **Note**: The `.tabula/` directory is git-ignored to prevent committing sensitive configuration.

### 5. Authenticate & Setup Cloud Resources

If you are setting up a new cloud environment (GCP Project), run:

```bash
tabcli infra setup
```

This will create the project (if needed), enable required APIs, and set up the Terraform state
bucket.

Then, authenticate with your services:

```bash
# Authenticate with GCP (CLI + Application Default Credentials)
tabcli auth gcloud

# Authenticate with Neon (API Key will be stored in Google Secret Manager)
tabcli auth neon
```

### 6. Configure Secrets

Secrets are handled automatically during infrastructure bootstrapping.

```bash
# Deploys infra and automatically syncs DATABASE_URL to your local config
tabcli infra bootstrap --env dev
```

If you need to manually pull secrets later:

```bash
tabcli infra secrets pull
```

### 7. Set Up Local Environment

```bash
# Setup local environment configuration (creates api/.env)
tabcli dev setup
```

> **Note**: `dev setup` creates `api/.env` from `.env.example`. Ensure `DATABASE_URL` in `api/.env`
> points to your local Docker Postgres instance
> (`postgresql://tabula:tabula_dev_password@localhost:5432/tabula_dev`) if you intend to develop
> locally.

### 8. Configure WorkOS Authentication

Tabula uses WorkOS AuthKit for secure SSO authentication. Set up a WorkOS account:

1. **Create WorkOS Account**:
   - Go to [workos.com](https://workos.com) and sign up
   - Create a new application for Tabula

2. **Configure Authentication Methods**:
   - Enable Google OAuth
   - Enable Microsoft OAuth (optional)
   - Enable GitHub OAuth (optional)
   - Enable Magic Link (optional)
   - Enable Password authentication (optional)

3. **Set Redirect URIs**:
   - Development: `http://localhost:8080/api/v1/auth/callback`
   - Production: `https://api.tabula.app/api/v1/auth/callback`

   > **Note**: You must manually add these URIs in the WorkOS Dashboard under **Configuration >
   > Redirect URIs**.

4. **Add Credentials to Environment**: Edit `api/.env` and add your WorkOS credentials:

   ```bash
   WORKOS_API_KEY=sk_test_your_api_key_here
   WORKOS_CLIENT_ID=client_your_client_id_here
   ```

   > **Note**: You can find these in the WorkOS Dashboard under "API Keys" and "Configuration"

5. **Generate JWT Secret**:

   ```bash
   # Generate a secure random secret
   node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
   ```

   Add it to `api/.env`:

   ```bash
   JWT_SECRET=your_generated_secret_here
   JWT_REFRESH_SECRET=your_generated_refresh_secret_here
   ```

### 9. Start Local Services

Start PostgreSQL and Redis using TabCLI:

```bash
tabcli dev start
```

This starts:

- PostgreSQL on port 5432
- Redis on port 6379

### 10. Initialize Database

To initialize the **local** database with the schema:

```bash
# Initialize local database (uses api/.env)
tabcli db init --local
```

> **Note**: Without the `--local` flag, `tabcli db init` targets the globally configured database
> (e.g., Neon/Cloud). Always use `--local` for local development.

### 11. Verify Setup

**Local Verification:**

```bash
# Verifies Node.js, dependencies, builds, tests, and linting
tabcli dev verify
```

**Infrastructure Verification:**

```bash
# Lists all deployed cloud resources
tabcli infra list --env dev
```

**Expected result:**

- `dev verify`: All checks pass.
- `infra list`: Displays Terraform state with Cloud Run, Neon DB, etc.

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
npm run dev --workspace=api
```

The API will be available at http://localhost:8080

### Build the Extension

```bash
npm run dev --workspace=extension
```

This watches for changes and rebuilds automatically.

### Load Extension in Chrome

1. Open Chrome and navigate to `chrome://extensions/`
2. Enable "Developer mode" (toggle in top right)
3. Click "Load unpacked"
4. Select the `extension/dist` directory
5. The extension should now appear in your browser

### Run All Services

```bash
# Start database and cache
tabcli dev start

# Start API in one terminal
npm run dev --workspace=api

# Start extension build in another terminal
npm run dev --workspace=extension
```

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
# Create preview (Neon Branch + Cloud Run)
tabcli infra preview up <pr-id>

# Destroy preview
tabcli infra preview down <pr-id>
```

### Running Tests

```bash
# Run all tests
tabcli dev test

# Run tests in watch mode
npm run test:watch --workspace=api

# Run tests with coverage
# Run tests with coverage
tabcli dev coverage --detailed
# or
npm run test:coverage

# Run specific test file
npm test --workspace=api -- tests/unit/auth.service.test.ts

# Run E2E tests
npm run test:e2e --workspace=extension
```

### Database Operations

```bash
# Create a new migration (local)
tabcli db migrate --local --name add_user_preferences

# Reset database (WARNING: deletes all data)
tabcli db reset --local

# Open Prisma Studio (database GUI)
tabcli db studio --local

# Generate Prisma client after schema changes
tabcli db init --local
```

### Linting and Formatting

```bash
# Lint all code
tabcli dev lint

# Fix linting issues
npm run lint:fix

# Check formatting
npm run format:check

# Format all code
npm run format
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

1. Update `api/prisma/schema.prisma`
2. Run `tabcli db migrate --local --name add_table_name`
3. Update TypeScript types if needed
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
# Check if PostgreSQL is running
tabcli dev start

# Restart services
tabcli dev stop
tabcli dev start

# Check logs (using docker directly for now)
docker-compose logs postgres
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
tabcli db init --local

# Check for TypeScript version conflicts
npm list typescript
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
