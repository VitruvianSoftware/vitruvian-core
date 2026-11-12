# Vitruvian Tabs CLI

Vitruvian Tabs CLI is a command-line interface tool for managing Vitruvian Tabs infrastructure and operations, similar
to `gcloud` for Google Cloud Platform.

## Features

- **Configuration Management**: Manage project settings and environment configuration
- **Database Operations**: Initialize, migrate, and manage PostgreSQL database
- **Secrets Management**: Securely store and retrieve secrets using Google Secret Manager
- **Deployment**: Deploy API services to Cloud Run and build extension bundles
- **Operational Workflows**: Handle all operational tasks that Terraform doesn't manage

## Installation

### From Source (Development)

```bash
# Install dependencies
npm install

# Build CLI
npm run build --workspace=cli

# Link globally (optional)
cd cli
npm link
```

### Usage in Project

```bash
# Using npm workspace
npm run dev --workspace=cli -- <command>

# Or after building
node cli/dist/index.js <command>

# If linked globally
vitruvian-tabs <command>
```

## Quick Start

### 1. Initialize Configuration

```bash
vitruvian-tabs init
```

This will prompt you for:

- GCP Project ID
- Default environment (development, staging, production)
- Default GCP region
- Database URL (optional)

Configuration is saved to `.vitruvian-tabs/config.json`.

### 2. Manage Configuration

```bash
# List all configuration
vitruvian-tabs config list

# Set a configuration value
vitruvian-tabs config set projectId my-project

# Get a configuration value
vitruvian-tabs config get environment

# Unset a configuration value
vitruvian-tabs config unset databaseUrl
```

### 3. Database Management

```bash
# Initialize database (run migrations)
vitruvian-tabs db init

# Run new migrations
vitruvian-tabs db migrate --name add_users_table

# Check migration status
vitruvian-tabs db status

# Open Prisma Studio (database GUI)
vitruvian-tabs db studio

# Reset database (WARNING: deletes all data)
vitruvian-tabs db reset --force
```

### 4. Secrets Management

```bash
# Set a secret (will prompt for value)
vitruvian-tabs infra secrets set DATABASE_URL

# Set a secret with value
vitruvian-tabs infra secrets set API_KEY --value "your-secret-key"

# Get a secret value
vitruvian-tabs infra secrets get DATABASE_URL

# List all secrets
vitruvian-tabs infra secrets list
```

### 5. Infrastructure & Deployment

```bash
# Bootstrap infrastructure (Terraform)
vitruvian-tabs infra bootstrap --env dev

# Deploy to staging
vitruvian-tabs infra deploy staging

# Deploy to production
vitruvian-tabs infra deploy production

# Deploy API only
vitruvian-tabs infra deploy staging --api

# Build extension only
vitruvian-tabs infra deploy staging --extension

# Check deployment status
vitruvian-tabs infra status staging
```

### 6. Development Workflow

```bash
# Start local services (Docker)
vitruvian-tabs dev start

# Stop local services
vitruvian-tabs dev stop

# Setup local environment
vitruvian-tabs dev setup

# Verify environment setup
vitruvian-tabs dev verify

# Run all checks (lint, test, build)
vitruvian-tabs dev check
```

### 7. Authentication

```bash
# Authenticate with Neon
vitruvian-tabs auth neon

# Authenticate with GCP
vitruvian-tabs auth gcloud
```

## Commands Reference

### Global Options

- `--help` - Display help for command
- `--version` - Display version information

### `init`

Initialize Vitruvian Tabs configuration.

```bash
vitruvian-tabs init [options]

Options:
  -f, --force  Overwrite existing configuration
```

### `config`

Manage configuration settings.

```bash
vitruvian-tabs config <subcommand>

Subcommands:
  list           List all configuration values
  set <key> <value>   Set a configuration value
  get <key>      Get a configuration value
  unset <key>    Unset a configuration value
```

### `db`

Database management commands.

```bash
vitruvian-tabs db <subcommand>

Subcommands:
  init           Initialize database with schema
  migrate        Run database migrations
  reset          Reset database (deletes all data)
  studio         Open Prisma Studio (database GUI)
  status         Check database connection and migration status
```

### `infra`

Manage cloud infrastructure and deployment.

```bash
vitruvian-tabs infra <subcommand>

Subcommands:
  bootstrap      Bootstrap cloud infrastructure using Terraform
  deploy         Deploy to a specific environment
  status         Check deployment status
  secrets        Manage secrets in Google Secret Manager
```

### `dev`

Local development environment management.

```bash
vitruvian-tabs dev <subcommand>

Subcommands:
  start          Start local development services (Docker)
  stop           Stop local development services
  setup          Setup local environment configuration
  verify         Verify development environment setup
  check          Run all checks (lint, test, build)
  test           Run tests
  lint           Run linter
  build          Run build
```

### `auth`

Manage authentication for external services.

```bash
vitruvian-tabs auth <subcommand>

Subcommands:
  neon           Authenticate with Neon
  gcloud         Authenticate with GCP
```

### `ext`

Manage the local load-unpacked dev extension install.

```bash
vitruvian-tabs ext <subcommand>

Subcommands:
  update         Download the latest rolling dev build into the load-unpacked directory
  path           Print the load-unpacked extension directory
```

#### `vitruvian-tabs ext update`

Downloads the rolling `vitruvian-tabs-extension-dev-latest` release from GitHub into
the load-unpacked directory, replacing any existing install atomically.

```bash
vitruvian-tabs ext update [options]

Options:
  --dir <path>        Extension directory (default: ~/.vitruvian-tabs/extension)
  --repo <owner/repo> GitHub repository     (default: VitruvianSoftware/vitruvian-core)
  --channel <name>    Release channel to track (default: installed channel, else alpha)
```

**Channels:**

| Channel | Tracks                                                |
| ------- | ----------------------------------------------------- |
| alpha   | every `main` commit (rolling dev-latest)              |
| beta    | the latest release cut (`vitruvian-tabs-extension-v*`)        |
| stable  | Web Store listing — prints guidance (arrives with M3) |

Passing `--channel` switches the installed channel permanently; subsequent bare
`vitruvian-tabs ext update` calls stay on it. See
[`apps/suites/vitruvian-tabs/extension/docs/DEV_UPDATES.md`](../extension/docs/DEV_UPDATES.md) for
the full channel reference including the dashboard banner behaviour.

Requires `gh` (authenticated via `gh auth login`) and `unzip` on PATH.

#### `vitruvian-tabs ext path`

Prints the resolved load-unpacked extension directory (useful for the
`chrome://extensions` → **Load unpacked** dialog).

```bash
vitruvian-tabs ext path [options]

Options:
  --dir <path>  Extension directory (default: ~/.vitruvian-tabs/extension)
```

For the full tester walkthrough, including the one-time setup and the
dashboard update banner, see
[`apps/suites/vitruvian-tabs/extension/docs/DEV_UPDATES.md`](../extension/docs/DEV_UPDATES.md).

### `version`

Show Vitruvian Tabs CLI and component versions.

```bash
vitruvian-tabs version
```

## Configuration File

Configuration is stored in `.vitruvian-tabs/config.json`:

```json
{
  "version": "0.1.0",
  "projectId": "vitruvian-tabs-dev",
  "environment": "development",
  "region": "us-central1",
  "databaseUrl": "postgresql://...",
  "createdAt": "2025-12-07T00:00:00.000Z"
}
```

## Prerequisites

- **Node.js** 18+
- **Google Cloud SDK** (gcloud) - For secrets and deployment commands
- **Docker** - For local database (when using `docker-compose`)

## Development

```bash
# Install dependencies
npm install

# Run in development mode
npm run dev --workspace=cli -- <command>

# Build
npm run build --workspace=cli

# Run tests
npm run test --workspace=cli

# Lint
npm run lint --workspace=cli
```

## Why Vitruvian Tabs CLI?

Vitruvian Tabs CLI handles operational workflows that Terraform doesn't manage:

- **Runtime Configuration**: Manage environment-specific settings
- **Secrets Management**: Securely store and rotate secrets
- **Database Operations**: Migrations, seeding, and maintenance
- **Deployment Automation**: Streamline deployment workflows
- **Developer Productivity**: Simplify common operational tasks

Instead of creating custom scripts for each task, Vitruvian Tabs CLI provides a unified, consistent interface
for all operational needs.

## Examples

### Complete Setup Workflow

```bash
# 1. Initialize configuration
vitruvian-tabs init

# 2. Authenticate
vitruvian-tabs auth neon
vitruvian-tabs auth gcloud

# 3. Bootstrap infrastructure
vitruvian-tabs infra bootstrap --env dev

# 4. Set up secrets
vitruvian-tabs infra secrets set DATABASE_URL
vitruvian-tabs infra secrets set JWT_SECRET
vitruvian-tabs infra secrets set JWT_REFRESH_SECRET

# 5. Initialize database
vitruvian-tabs db init

# 6. Deploy to staging
vitruvian-tabs infra deploy staging

# 7. Check deployment
vitruvian-tabs infra status staging
```

### Daily Development Workflow

```bash
# Start local environment
vitruvian-tabs dev start

# Run checks
vitruvian-tabs dev check

# Run new migration
vitruvian-tabs db migrate --name add_new_feature

# Update secret
vitruvian-tabs infra secrets set NEW_API_KEY

# Deploy changes
vitruvian-tabs infra deploy staging
```

## Skaffold vs Docker Compose

**For Local Development**: We use **Docker Compose** for the following reasons:

- **Simplicity**: Easier to understand and configure for local development
- **Familiarity**: More developers are familiar with Docker Compose
- **Purpose-built**: Designed specifically for local development environments
- **Current Architecture**: Our simple setup (1 API + 1 extension + database/Redis) doesn't require
  Skaffold's orchestration

**Skaffold** is excellent for:

- Continuous deployment workflows with file watching and auto-rebuilds
- Cloud Run deployments (supported in recent versions)
- Complex microservices architectures with multiple containerized services
- Teams requiring coordinated deployments across multiple services
- Advanced build orchestration with dependency management

**Why Not Skaffold (For Now)**:

While Skaffold does support Cloud Run and offers powerful continuous development features, it adds
complexity that isn't justified for our current architecture. Skaffold would still use Docker
Compose underneath for local development, and our deployment needs are well-served by Vitruvian Tabs CLI's
simpler approach.

**When to Reconsider**: If we evolve to a microservices architecture with multiple containerized
services requiring coordinated deployments, Skaffold would be worth adopting.

**Our Choice**: Stick with **Docker Compose** for local development. Use **Vitruvian Tabs CLI** + **Terraform**
for infrastructure management and **GitHub Actions** for CI/CD. This provides a simpler, more
maintainable stack that meets all current requirements.

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for development guidelines.

## License

MIT License - see [LICENSE](../LICENSE) for details.

## Subdirectories & Boundaries
- [rs](./rs/README.md): Subsystem blueprint grouping child modules under apps/suites/vitruvian-tabs/cli/rs.

