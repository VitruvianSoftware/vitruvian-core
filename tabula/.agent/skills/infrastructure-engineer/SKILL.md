---
name: Infrastructure Engineer
description: Expert guidance for managing Tabula's GCP infrastructure using Terraform
---

# Infrastructure Engineer

You are an expert infrastructure engineer specializing in Tabula's GCP cloud infrastructure.

## Technology Stack

- **Terraform 1.6+** for Infrastructure as Code
- **Google Cloud Platform**:
  - Cloud Run (serverless compute)
  - Cloud Storage (backups, assets)
  - Cloud Scheduler (cron jobs)
  - Pub/Sub (event messaging)
  - Secret Manager
- **Neon** (serverless Postgres)
- **Upstash** (serverless Redis)
- **Cloudflare** (CDN)

## Project Structure

```
infrastructure/
├── modules/           # Reusable Terraform modules
│   ├── gcp-cloud-run/     # API deployment
│   ├── neon-database/     # Neon configuration
│   ├── gcp-storage/       # GCS buckets
│   └── gcp-scheduler/     # Cron jobs
├── environments/      # Environment-specific configs
│   ├── dev/
│   ├── staging/
│   └── prod/
├── providers.tf       # Provider configuration
└── versions.tf        # Version constraints
```

## Key Infrastructure Components

### Cloud Run API

```hcl
# modules/gcp-cloud-run/main.tf
resource "google_cloud_run_v2_service" "api" {
  name     = "tabula-api"
  location = var.region

  template {
    scaling {
      min_instance_count = 0   # Scale to zero
      max_instance_count = 100
    }

    containers {
      image = var.api_image
      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }
  }
}
```

### Cloud Scheduler Jobs

```hcl
# Backup job (every 6 hours)
resource "google_cloud_scheduler_job" "backup" {
  name        = "tabula-backup"
  schedule    = "0 */6 * * *"
  http_target {
    uri         = "${google_cloud_run_v2_service.api.uri}/api/v1/jobs/backup"
    oidc_token {
      service_account_email = google_service_account.scheduler.email
    }
  }
}
```

### Secret Manager

```hcl
# Store sensitive configuration
resource "google_secret_manager_secret" "database_url" {
  secret_id = "DATABASE_URL"
  replication {
    auto {}
  }
}
```

## TabCLI Infrastructure Commands

```bash
# Bootstrap infrastructure (Terraform)
tabcli infra bootstrap --env dev

# Deploy to environment
tabcli infra deploy staging

# Check deployment status
tabcli infra status staging

# Manage secrets
tabcli infra secrets set DATABASE_URL
tabcli infra secrets pull

# Preview environments (PR-based)
tabcli infra preview up 123
tabcli infra preview down 123
```

## Environment Configuration

Each environment has its own Terraform state:

```bash
# environments/staging/main.tf
module "api" {
  source = "../../modules/gcp-cloud-run"

  project_id = var.project_id
  region     = "us-central1"
  env        = "staging"
  api_image  = "gcr.io/${var.project_id}/tabula-api:${var.api_version}"
}
```

## Cost Optimization

- **Cloud Run**: Scale-to-zero (no idle costs)
- **Neon**: Autosuspend after 5 minutes
- **Upstash**: Serverless Redis (pay per command)
- **Cloud Storage**: Lifecycle policies for backup retention

Estimated cost at 10K users: ~$95-100/month

## Common Hazards

1. **Neon Authentication Trap**: Database connection requires SSL and pooler URL format
2. **Terraform State**: Always use remote state in Cloud Storage
3. **Secret Manager Access**: Cloud Run service account needs `secretAccessor` role
4. **Upstash**: No Terraform provider - configure manually via dashboard

## Key Files to Reference

- [Infrastructure README](file:///Users/james/Workspace/gh/lab/tabula/infrastructure/README.md)
- [Implementation Status](file:///Users/james/Workspace/gh/lab/tabula/infrastructure/IMPLEMENTATION_STATUS.md)
- [Architecture Overview](file:///Users/james/Workspace/gh/lab/tabula/docs/architecture/overview.md)
- [CLI Reference](file:///Users/james/Workspace/gh/lab/tabula/docs/reference/cli.md)
