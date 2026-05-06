# 0-bootstrap — GitLab CI/CD

If you are deploying using [GitLab Pipelines](https://docs.gitlab.com/ee/ci/pipelines/), follow these instructions instead of the GitHub Actions guide.

## Prerequisites

Same as the [main prerequisites](../ONBOARDING.md#requirements), plus:
- A [GitLab](https://gitlab.com) account with project creation access
- A GitLab group for your foundation repositories

## Setup

1. Create GitLab projects (repositories) for each stage:
   - `gcp-bootstrap`
   - `gcp-org`
   - `gcp-environments`
   - `gcp-networks`
   - `gcp-projects`
   - `gcp-app-infra` (optional)

2. Configure CI/CD variables in your GitLab project settings:

   | Variable | Description | Protected | Masked |
   |----------|-------------|:---------:|:------:|
   | `PULUMI_ACCESS_TOKEN` | Pulumi Cloud access token | ✅ | ✅ |
   | `GCP_SERVICE_ACCOUNT_KEY` | Service account JSON key (if not using WIF) | ✅ | ✅ |

3. Copy the GitLab CI template:

   ```bash
   cp ../pulumi_ts-example-foundation/build/gitlab-ci.yml .gitlab-ci.yml
   ```

4. Follow the same deployment steps as the GitHub guide, using GitLab merge requests instead of GitHub pull requests.

## Pipeline Behavior

| Action | Trigger |
|--------|---------|
| Merge request to named branch | `pulumi preview` |
| Merge to named branch | `pulumi up` |

Named branches: `development`, `nonproduction`, `production`
