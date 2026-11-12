# Pulumi Platform: Sentry

First-party self-hosted Sentry infrastructure as code: manages teams, projects, client keys (DSNs), and default issue alerts against our homelab Sentry instance (`https://sentry.lab.ipv1337.dev/api/`).

## Stacks

- **`production`**: The production self-hosted Sentry stack.

## Commands

Run via the standard Bazel targets:

```bash
# Preview changes
bazel run //infrastructure/pulumi/platform/sentry:preview

# Apply changes (from main, through CI or manually)
bazel run //infrastructure/pulumi/platform/sentry:up
```
