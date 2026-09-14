# Operations Guide

This guide provides instructions for operators and administrators responsible for deploying,
managing, and maintaining the Tabula platform.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Infrastructure Deployment](#infrastructure-deployment)
- [Application Deployment](#application-deployment)
- [Database Management](#database-management)
- [Monitoring & Troubleshooting](#monitoring--troubleshooting)
- [Disaster Recovery](#disaster-recovery)

## Prerequisites

Before you begin, ensure you have the following tools installed:

- **Terraform** (>= 1.6.0)
- **Google Cloud SDK** (`gcloud`)
- **Node.js** (>= 18)
- **TabCLI** (Tabula Command Line Interface)

See [Infrastructure Setup](../reference/infrastructure.md) for detailed installation instructions.

## Third-Party Service Setup

Tabula relies on several third-party services that must be configured before deploying the
application.

### 1. Neon Postgres (Database)

Neon provides serverless Postgres. The project `tabula` is already configured with the following
structure:

- **Project Name**: `tabula`
- **Region**: AWS US East 2 (Ohio)
- **Branches**:
  - `production` (Default): Used for the production environment (Autoscaling .25 - 2 CU).
  - `development`: Used for development/staging environments (Autoscaling .25 - 1 CU).

To configure the application:

1.  **Get Connection String**:
    - Go to the **Dashboard** in Neon.
    - Select the **Branch** corresponding to your environment (`production` or `development`).
    - Copy the connection string (e.g.,
      `postgres://user:pass@ep-xyz.us-east-2.aws.neon.tech/neondb`).

2.  **Configure Secrets**:

    Ensure your `tabcli` is configured for the correct **Google Cloud Platform (GCP) Project ID**
    before setting secrets. These secrets are stored in Google Secret Manager.

    ```bash
    # For Production
    # 1. Switch to production GCP project if needed
    # tabcli config set projectId <gcp-prod-project-id>

    # 2. Set the secret (use quotes to handle special characters)
    tabcli infra secrets set DATABASE_URL --value "<production-connection-string>"

    # For Development
    # 1. Switch to development GCP project if needed
    # tabcli config set projectId <gcp-dev-project-id>

    # 2. Set the secret
    tabcli infra secrets set DATABASE_URL --value "<development-connection-string>"
    ```

### 2. Upstash Redis (Caching)

Upstash provides serverless Redis for caching and session management.

1.  **Create Database**: Sign up at [upstash.com](https://upstash.com) and create a new Redis
    database.
2.  **Get Credentials**: Copy the Redis Connection URL (starts with `rediss://`).
3.  **Configure Secrets**:
    ```bash
    tabcli infra secrets set UPSTASH_REDIS_URL --value "rediss://default:password@..."
    ```

### 3. WorkOS (Authentication)

WorkOS handles SSO, directory sync, and user management. Tabula uses the **WorkOS Staging**
environment for development and staging, and **WorkOS Production** for the live application.

#### Prerequisites

- WorkOS Account (Free Tier is sufficient for Dev/Staging).
- **WorkOS CLI**: Installed automatically in the devcontainer, or install via Homebrew:
  `brew install workos/tap/workos-cli`.

#### Configuration Steps

1.  **Get Credentials**:
    - Log in to the [WorkOS Dashboard](https://dashboard.workos.com/).
    - Navigate to **Developer** (or Configuration) -> **API Keys**.
    - Copy the **Client ID** (starts with `client_`) and **API Key** (starts with `sk_test_` or
      `sk_prod_`).

2.  **Configure Secrets**: Store these credentials in Google Secret Manager using `tabcli`.

    ```bash
    # Set Client ID (Public identifier)
    tabcli infra secrets set WORKOS_CLIENT_ID --value "client_..."

    # Set API Key (Secret key)
    tabcli infra secrets set WORKOS_API_KEY --value "sk_test_..."
    ```

3.  **Manage Organizations via CLI**: Tabula provides a wrapper around the WorkOS CLI to handle
    authentication automatically (injecting the secrets set above).

    ```bash
    # List organizations
    tabcli workos organization list

    # Create a new organization (Note: strict validation on free tier)
    tabcli workos organization create "Tabula Dev" --allow-domain tabula.io
    ```

    > **Note**: On the WorkOS Free Tier, organization creation via CLI might fail with
    > `422 Unprocessable Entity` due to domain validation or unique name constraints. In this case,
    > use the [WorkOS Dashboard](https://dashboard.workos.com/) to create your organization
    > manually.

#### Troubleshooting

- **401 Unauthorized**:
  - **Cause**: The `WORKOS_API_KEY` is missing or invalid.
  - **Fix**: Verify the secret exists: `tabcli infra secrets get WORKOS_API_KEY` (or checking GCP
    console). Ensure it matches the key in the WorkOS Dashboard.

- **422 Unprocessable Entity**:
  - **Cause**: Validation error during resource creation (e.g., domain verification required,
    duplicate name).
  - **Fix**: Check the error message details. Try creating the resource via the WorkOS Dashboard for
    more granular feedback.

- **CLI "Headless" Mode**:
  - `tabcli` automatically configures the WorkOS CLI in "headless" mode using your secrets. You do
    **not** need to run `workos init` or login interactively.

## Infrastructure Deployment

Tabula uses Terraform to manage its cloud infrastructure on Google Cloud Platform (GCP) and Neon.

### Environment Strategy

- **Development (`dev`)**: Managed via Terraform in `infrastructure/environments/dev`.
- **Production (`prd`)**: Managed via Terraform in `infrastructure/environments/prd`.
- **Staging**: A hybrid environment. It is **not** managed by Terraform. Instead, it is deployed as
  a standalone Cloud Run service within the **Development** GCP project using `gcloud` commands (via
  `tabcli` or GitHub Actions). It shares the development database and secrets but runs a separate
  instance of the API.

### 1. Bootstrap Infrastructure

To set up the initial infrastructure, use `tabcli`:

```bash
# Bootstrap infrastructure for development
tabcli infra bootstrap --env dev

# Bootstrap infrastructure for production
tabcli infra bootstrap --env prod
```

This command handles:

- Initializing Terraform
- Creating the Terraform state bucket (if not exists)
- Applying the Terraform configuration

For more details, refer to the [Infrastructure Reference](../reference/infrastructure.md).

## Application Deployment

### Deploying the API

The API service is deployed to Google Cloud Run. You can use `tabcli` to manage deployments.

```bash
# Deploy to production
tabcli deploy api --env production
```

### Publishing the Extension

The browser extension is published to the Chrome Web Store.

1.  Build the extension bundle:

    ```bash
    npm run build --workspace=extension
    ```

2.  The build artifacts will be in `extension/dist`. Upload the zip file to the Chrome Web Store
    Developer Dashboard.

## Database Management

Tabula uses Prisma for database schema management.

### Running Migrations

To apply database migrations in production:

```bash
tabcli db migrate --env production
```

### Database Backups

Database backups are managed automatically by Neon. You can also trigger manual backups via the Neon
console or `tabcli` if configured.

## Monitoring & Troubleshooting

### Logs

Access application logs via Google Cloud Logging:

```bash
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=tabula-api" --limit 10
```

### Health Checks

The API exposes a health check endpoint at `/health`.

```bash
curl https://api.tabula.app/health
```

## Disaster Recovery

In the event of a catastrophic failure:

1.  **Database Restoration**: Use Neon's point-in-time recovery features to restore the database to
    a known good state.
2.  **Infrastructure Re-provisioning**: Run `terraform apply` to recreate missing infrastructure
    components.
