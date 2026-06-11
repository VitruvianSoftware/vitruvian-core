# Tabula Infrastructure

This directory contains Terraform Infrastructure as Code (IaC) for deploying Tabula's cloud
infrastructure. The architecture leverages serverless and managed services to minimize operational
costs while maintaining scalability and reliability.

## Architecture Overview

Tabula uses a lean, cost-effective cloud architecture:

- **Compute**: Google Cloud Run (serverless, scale-to-zero)
- **Database**: Neon Postgres (serverless, autoscaling)
- **Cache**: Upstash Redis (serverless, edge-optimized)
- **Storage**: Google Cloud Storage (backups, static assets)
- **Scheduler**: Google Cloud Scheduler (background jobs)
- **Auth**: WorkOS (SSO, SCIM for enterprise features)

See [Architecture Documentation](../architecture/overview.md) for detailed system design.

## Directory Structure

```
infrastructure/
├── README.md                # This file
├── versions.tf              # Terraform and provider version constraints
├── providers.tf             # Provider configurations
├── environments/
│   ├── dev/                 # Development environment
│   │   ├── main.tf          # Main infrastructure configuration
│   │   ├── variables.tf     # Input variables
│   │   ├── outputs.tf       # Output values
│   │   └── terraform.tfvars.example  # Example variable values
│   └── prod/                # Production environment
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── terraform.tfvars.example
└── modules/

> **Note:** The **Staging** environment is not managed via Terraform. It is deployed imperatively to the Development GCP project as a separate Cloud Run service (`tabula-api-stg`) using the `tabcli` or CI/CD pipeline. It shares the development database and secrets.

    ├── gcp-cloud-run/       # Cloud Run API service
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── gcp-storage/         # Cloud Storage buckets
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── gcp-scheduler/       # Cloud Scheduler jobs
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── neon-database/       # Neon Postgres database
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

## Prerequisites

### 1. Install Required Tools

- **Terraform**: >= 1.6.0

  ```bash
  brew install terraform  # macOS
  # or download from https://www.terraform.io/downloads
  ```

- **gcloud CLI**: For GCP authentication
  ```bash
  brew install google-cloud-sdk  # macOS
  # or see https://cloud.google.com/sdk/docs/install
  ```

### 2. Set Up GCP Project

Use `tabcli` to automate the project setup:

```bash
# 1. Initialize configuration
tabcli init

# 2. Setup GCP project (creates project, enables APIs, creates state bucket)
tabcli infra setup
```

This command handles:

- Project creation (if it doesn't exist)
- Billing verification
- Enabling required APIs (Cloud Run, Secret Manager, etc.)
- Creating the Terraform state bucket

### 3. Bootstrap Infrastructure

Once the project is set up and secrets are configured (see below), run the bootstrap command to
deploy the infrastructure:

```bash
tabcli infra bootstrap
```

This command:

- Initializes Terraform
- Prompts for any missing configuration (e.g., Neon Organization ID)
- Applies the Terraform configuration to create Cloud Run services, Databases, etc.
- Automatically updates local secrets with the outputs (e.g., `DATABASE_URL`)

### 4. Set Up Neon Database

Neon provides serverless Postgres with a generous free tier.

1. Sign up at https://neon.tech
2. Create an API key:
   - Go to Account Settings → API Keys
   - Create a new API key
   - Save it securely

3. Set the API key as environment variable:
   ```bash
   export NEON_API_KEY="your-api-key-here"
   ```

**Note**: The bootstrap command will prompt for your Neon Organization ID if it's not in your
config. You can find this in the Neon Console settings.

### 5. Set Up Upstash Redis

**Note**: Upstash does not have an official Terraform provider. Manual setup required.

1. Sign up at https://upstash.com
2. Create a Redis database:
   - Region: Choose closest to your users (or Global for edge caching)
   - Type: Regional or Global
   - Enable TLS
3. Copy the Redis Connection URL (starts with `rediss://` and includes the password)
4. Add to Google Secret Manager:
   ```bash
   # After Terraform creates Secret Manager resources
   npm run dev --workspace=cli -- infra secrets set UPSTASH_REDIS_URL -v "rediss://default:password@..."
   ```

### 6. Set Up WorkOS (Optional - Phase 4)

**Note**: WorkOS Terraform provider is community-maintained. Dashboard configuration recommended.

1. Sign up at https://workos.com
2. Create an organization
3. Get API key from dashboard
4. Add to Secret Manager:
   ```bash
   npm run dev --workspace=cli -- infra secrets set WORKOS_API_KEY -v "your-workos-api-key"
   ```

### 7. Configure Terraform Backend

The `tabcli infra setup` command automatically creates a Google Cloud Storage bucket for Terraform
state (e.g., `gs://<project-id>-tf-state`).

To enable remote state:

1. Uncomment the `backend "gcs"` block in `environments/*/main.tf`.
2. Ensure the `bucket` name matches the one created by `infra setup`.

## Usage

### Development Environment

Bootstrap the development environment using TabCLI:

```bash
npm run dev --workspace=cli -- infra bootstrap --env dev
```

This command will:

1. Check prerequisites (Terraform, gcloud)
2. Configure `terraform.tfvars` interactively
3. Initialize Terraform
4. Apply the configuration
5. Automatically update secrets from outputs

### Production Environment

Bootstrap the production environment:

```bash
npm run dev --workspace=cli -- infra bootstrap --env prod
```

**Important for Production:**

- Use separate GCP project from dev
- Review all security settings
- Enable audit logging
- Set up monitoring and alerts
- Configure backup retention policies
- Use Terraform workspaces or separate state files

## Module Documentation

### neon-database

Creates a Neon Postgres project, database, and optional dev branch.

**Features:**

- Autoscaling compute (scale to zero)
- Configurable suspend timeout
- Branch support for dev environments
- PostgreSQL 16

**Example Usage:**

```hcl
module "database" {
  source = "../../modules/neon-database"

  project_name         = "tabula-dev"
  region              = "aws-us-east-1"
  pg_version          = 16
  autoscaling_min     = 0.25
  autoscaling_max     = 2
  suspend_timeout     = 300
  create_dev_branch   = true
}
```

### gcp-cloud-run

Deploys a Cloud Run service with configurable scaling and environment variables.

**Features:**

- Scale to zero
- Custom domain mapping (optional)
- Environment variables and secrets
- Public or private access
- OIDC authentication support

**Example Usage:**

```hcl
module "api" {
  source = "../../modules/gcp-cloud-run"

  project_id      = var.gcp_project_id
  region          = var.gcp_region
  service_name    = "tabula-api"
  image           = "gcr.io/${var.gcp_project_id}/tabula-api:latest"

  environment_variables = {
    NODE_ENV = "production"
  }

  secrets = {
    DATABASE_URL = google_secret_manager_secret.database_url.id
  }
}
```

### gcp-storage

Creates Cloud Storage buckets with lifecycle policies and CORS configuration.

**Features:**

- Separate buckets for backups and assets
- Lifecycle rules (transition to NEARLINE, auto-delete)
- CORS configuration for web access
- Optional public access
- Versioning support

**Example Usage:**

```hcl
module "storage" {
  source = "../../modules/gcp-storage"

  project_id          = var.gcp_project_id
  region              = var.gcp_region
  backup_bucket_name  = "tabula-backups-prod"
  assets_bucket_name  = "tabula-assets-prod"
  backup_retention_days = 90
}
```

### gcp-scheduler

Creates Cloud Scheduler jobs for background tasks.

**Features:**

- OIDC authentication to Cloud Run
- Configurable schedules
- Retry policies
- Multiple job types (backup, cleanup, sync)

**Example Usage:**

```hcl
module "scheduler" {
  source = "../../modules/gcp-scheduler"

  project_id     = var.gcp_project_id
  region         = var.gcp_region
  api_url        = module.api.service_url
  service_account_email = google_service_account.api.email
}
```

## Environment Variables

The following secrets need to be created in Google Secret Manager:

- `DATABASE_URL`: Neon database connection string
- `UPSTASH_REDIS_URL`: Upstash Redis REST API URL
- `WORKOS_API_KEY`: WorkOS API key (Phase 4)

Create secrets after running Terraform (Note: `bootstrap-infra` automatically sets `DATABASE_URL`):

```bash
# Set Upstash Redis URL
npm run dev --workspace=cli -- infra secrets set UPSTASH_REDIS_URL -v "your-upstash-url"

# Set WorkOS API Key (Phase 4)
npm run dev --workspace=cli -- infra secrets set WORKOS_API_KEY -v "your-workos-api-key"
```

The `bootstrap-infra` command automatically handles the IAM bindings for the service account.

## Cost Estimation

### Free Tier Limits (Monthly)

- **Cloud Run**: 2M requests, 360,000 GB-seconds compute
- **Neon**: 0.5 GB storage, autoscaling to zero
- **Upstash**: 10,000 commands/day
- **Cloud Storage**: 5 GB storage, 5,000 Class A operations
- **Cloud Scheduler**: 3 jobs free
- **Pub/Sub**: 10 GB message delivery
- **Secret Manager**: 6 active secrets
- **WorkOS**: 1M MAUs free

### Estimated Costs at 1,000 Users

- **Cloud Run**: ~$10/month (beyond free tier)
- **Neon**: ~$5/month
- **Upstash**: $0 (within free tier)
- **Cloud Storage**: ~$2/month
- **Cloud Scheduler**: ~$0.10/month
- **Pub/Sub**: ~$1/month
- **WorkOS**: $0 (under 1M MAUs)

**Total**: ~$18-20/month at 1,000 users (~$0.02 per user)

### Estimated Costs at 10,000 Users

- **Cloud Run**: ~$50/month
- **Neon**: ~$20/month
- **Upstash**: ~$10/month
- **Cloud Storage**: ~$10/month
- **Cloud Scheduler**: ~$0.30/month
- **Pub/Sub**: ~$5/month

**Total**: ~$95-100/month at 10,000 users (~$0.01 per user)

## Monitoring

After deploying infrastructure:

1. **Set up Cloud Monitoring Dashboard**:
   - Go to Cloud Console → Monitoring
   - Create custom dashboard
   - Add metrics: API latency, error rate, request count

2. **Configure Alerts**:

   ```bash
   # Example: Alert on high error rate
   gcloud alpha monitoring policies create \
     --notification-channels=CHANNEL_ID \
     --display-name="High API Error Rate" \
     --condition-display-name="Error rate > 1%" \
     --condition-threshold-value=0.01 \
     --condition-threshold-duration=300s
   ```

3. **Monitor Costs**:
   - Enable budget alerts in GCP Console
   - Set budget threshold (e.g., $50/month for dev)
   - Configure email notifications

## Troubleshooting

### Common Issues

**1. "API not enabled" errors**

```bash
# Enable required APIs
gcloud services enable cloudrun.googleapis.com storage.googleapis.com
```

**2. "Permission denied" errors**

```bash
# Ensure you're authenticated
gcloud auth application-default login

# Check your permissions
gcloud projects get-iam-policy PROJECT_ID
```

**3. Neon provider authentication issues**

```bash
# Verify NEON_API_KEY is set
echo $NEON_API_KEY

# Set if missing
export NEON_API_KEY="your-key-here"
```

**4. Terraform state lock errors**

```bash
# If using remote backend and state is locked
terraform force-unlock LOCK_ID
```

**5. Cloud Run deployment timeouts**

- Increase timeout in `main.tf`: `timeout_seconds = 300`
- Check Cloud Build logs for image build issues
- Verify image exists in Artifact Registry

## Security Best Practices

1. **Never commit `terraform.tfvars` to Git**
   - Already in `.gitignore`
   - Use `terraform.tfvars.example` as template

2. **Use Secret Manager for sensitive values**
   - Don't pass secrets as plain environment variables
   - Reference secrets in Cloud Run configuration

3. **Rotate API keys regularly**
   - Neon API key: every 90 days
   - Service account keys: every 90 days
   - Update in Terraform and re-apply

4. **Limit service account permissions**
   - Use principle of least privilege
   - Review IAM bindings regularly

5. **Enable audit logging**
   - Already enabled in Terraform configurations
   - Review logs in Cloud Console

## Maintenance

### Regular Tasks

**Weekly:**

- Review Cloud Monitoring dashboards
- Check error logs in Cloud Logging
- Verify backup jobs are running

**Monthly:**

- Review GCP billing
- Update Terraform providers
- Review and rotate access keys
- Check for Terraform state drift

**Quarterly:**

- Update Terraform modules
- Review security settings
- Audit IAM permissions
- Test disaster recovery procedures

### Upgrading

1. Update provider versions in `versions.tf`
2. Run `terraform init -upgrade`
3. Review `terraform plan` carefully
4. Test in dev environment first
5. Apply to production after validation

## Support

### Getting Help

1. **Documentation**: See [Architecture docs](../architecture/overview.md)
2. **Issues**: Check GitHub issues for known problems
3. **Community**: Join discussions in GitHub Discussions

### Useful Links

- [Terraform GCP Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Neon Terraform Provider](https://registry.terraform.io/providers/kislerdm/neon/latest/docs)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Neon Documentation](https://neon.tech/docs)
- [Upstash Documentation](https://docs.upstash.com)
- [WorkOS Documentation](https://workos.com/docs)

---

_Last Updated: 2025-12-07_
