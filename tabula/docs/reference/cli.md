# TabCLI

TabCLI is a command-line interface tool for managing Tabula infrastructure and operations, similar
to `gcloud` for Google Cloud Platform.

## Features

- **Configuration Management**: Manage project settings and environment configuration
- **Database Operations**: Initialize, migrate, and manage PostgreSQL database
- **Secrets Management**: Securely store and retrieve secrets using Google Secret Manager
- **Deployment**: Deploy API services to Cloud Run and build extension bundles
- **Operational Workflows**: Handle all operational tasks that Terraform doesn't manage
- **Idempotency**: All commands are designed to be safe to re-run and automation-friendly (see
  [ADR-005](../architecture/adr/005-cli-idempotency.md))

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
tabcli <command>
```

## Quick Start

### 1. Initialize Configuration

```bash
tabcli init
```

This will prompt you for:

- GCP Project ID
- Default environment (development, staging, production)
- Default GCP region
- Database URL (optional)

Configuration is saved to `.tabula/config.json`.

### 2. Manage Configuration

```bash
# List all configuration
tabcli config list

# Set a configuration value
tabcli config set projectId my-project

# Get a configuration value
tabcli config get environment

# Unset a configuration value
tabcli config unset databaseUrl
```

### 3. Database Management

> **Note**: Database commands target the database configured in `.tabula/config.json` (via
> `databaseUrl`). If `databaseUrl` is not set, they may fall back to environment variables or local
> configuration. For purely local development with Docker, ensure you are targeting the correct
> database.

```bash
# Initialize database (run migrations)
tabcli db init

# Run new migrations
tabcli db migrate --name add_users_table

# Check migration status
tabcli db status

# Open Prisma Studio (database GUI)
tabcli db studio

# Reset database (WARNING: deletes all data)
tabcli db reset --force
```

### 4. Secrets Management

```bash
# Set a secret (will prompt for value)
tabcli infra secrets set DATABASE_URL

# Set a secret with value flag
tabcli infra secrets set API_KEY --value "your-secret-key"

# Get a secret value
tabcli infra secrets get DATABASE_URL

# List all secrets
tabcli infra secrets list

# Pull secrets to local configuration
tabcli infra secrets pull
```

### 5. Infrastructure & Deployment

```bash
# Setup GCP project (enable APIs, create state bucket)
tabcli infra setup

# Bootstrap infrastructure (Terraform)
tabcli infra bootstrap --env dev

# Deploy to staging
tabcli infra deploy staging

# Deploy to production
tabcli infra deploy production

# Deploy API only
tabcli infra deploy staging --api

# Build extension only
tabcli infra deploy staging --extension

# Check deployment status
tabcli infra status staging

# Create a preview environment for PR #123
tabcli infra preview up 123

# Destroy preview environment for PR #123
tabcli infra preview down 123
```

### 6. Development Workflow

```bash
# Start local services (Docker)
tabcli dev start

# Stop local services
tabcli dev stop

# Setup local environment
tabcli dev setup

# Verify environment setup
tabcli dev verify

# Run all checks (lint, test, build)
tabcli dev check
```

### 7. Authentication

```bash
# Authenticate with Neon
tabcli auth neon

# Authenticate with GCP
tabcli auth gcloud
```

## Commands Reference

### Global Options

- `--help` - Display help for command
- `--version` - Display version information

### `init`

Initialize Tabula configuration.

```bash
tabcli init [options]

Options:
  -f, --force  Overwrite existing configuration
```

### `config`

Manage configuration settings.

```bash
tabcli config <subcommand>

Subcommands:
  list           List all configuration values
  set <key> <value>   Set a configuration value
  get <key>      Get a configuration value
  unset <key>    Unset a configuration value
```

### `db`

Database management commands.

```bash
tabcli db <subcommand>

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
tabcli infra <subcommand>

Subcommands:
  bootstrap      Bootstrap cloud infrastructure using Terraform
  deploy         Deploy to a specific environment
  status         Check deployment status
  secrets        Manage secrets in Google Secret Manager
```

### `dev`

Local development environment management.

```bash
tabcli dev <subcommand>

Subcommands:
  start          Start local development services (Docker)
  stop           Stop local development services
  setup          Setup local environment configuration
  verify         Verify development environment setup
  check          Run all checks (lint, test, build)
  test           Run tests
  coverage       Run tests with coverage (use --detailed for breakdown)
  lint           Run linter
  build          Run build
```

### `auth`

Manage authentication for external services.

```bash
tabcli auth <subcommand>

Subcommands:
  neon           Authenticate with Neon
  gcloud         Authenticate with GCP
```

### `github`

Manage GitHub repository configuration.

```bash
tabcli github <subcommand>

Subcommands:
  secrets sync   Sync secrets from Terraform/GCP to GitHub
  secrets list   List current GitHub repository secrets
  secrets set    Set a single GitHub secret
  status         Check GitHub Actions and repository status
```

**Examples:**

```bash
# Sync secrets from dev environment to GitHub
tabcli github secrets sync --env dev

# Dry run to see what would be synced
tabcli github secrets sync --env dev --dry-run

# List current GitHub secrets
tabcli github secrets list

# Set a single secret manually
tabcli github secrets set CODECOV_TOKEN

# Check overall GitHub status
tabcli github status
```

### `version`

Show TabCLI and component versions.

```bash
tabcli version
```

## Configuration File

Configuration is stored in `.tabula/config.json`:

```json
{
  "version": "0.1.0",
  "projectId": "tabula-dev",
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

## Why TabCLI?

TabCLI handles operational workflows that Terraform doesn't manage:

- **Runtime Configuration**: Manage environment-specific settings
- **Secrets Management**: Securely store and rotate secrets
- **Database Operations**: Migrations, seeding, and maintenance
- **Deployment Automation**: Streamline deployment workflows
- **Developer Productivity**: Simplify common operational tasks

Instead of creating custom scripts for each task, TabCLI provides a unified, consistent interface
for all operational needs.

## Examples

### Complete Setup Workflow

```bash
# 1. Initialize configuration
tabcli init

# 2. Authenticate
tabcli auth neon
tabcli auth gcloud

# 3. Bootstrap infrastructure
tabcli infra bootstrap --env dev

# 4. Set up secrets
tabcli infra secrets set DATABASE_URL
tabcli infra secrets set JWT_SECRET
tabcli infra secrets set JWT_REFRESH_SECRET

# 5. Initialize database
tabcli db init

# 6. Sync secrets to GitHub (for CI/CD)
tabcli github secrets sync --env dev

# 7. Deploy to staging
tabcli infra deploy staging

# 8. Check deployment
tabcli infra status staging
```

### Daily Development Workflow

```bash
# Start local environment
tabcli dev start

# Run checks
tabcli dev check

# Run new migration
tabcli db migrate --name add_new_feature

# Update secret
tabcli infra secrets set NEW_API_KEY

# Deploy changes
tabcli infra deploy staging
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
Compose underneath for local development, and our deployment needs are well-served by TabCLI's
simpler approach.

**When to Reconsider**: If we evolve to a microservices architecture with multiple containerized
services requiring coordinated deployments, Skaffold would be worth adopting.

**Our Choice**: Stick with **Docker Compose** for local development. Use **TabCLI** + **Terraform**
for infrastructure management and **GitHub Actions** for CI/CD. This provides a simpler, more
maintainable stack that meets all current requirements.

## Contributing

See [CONTRIBUTING.md](../../CONTRIBUTING.md) for development guidelines.

## License

MIT License - see [LICENSE](../../../LICENSE) for details.
