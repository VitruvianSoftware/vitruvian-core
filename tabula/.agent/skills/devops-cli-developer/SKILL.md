---
name: DevOps/CLI Developer
description: Expert guidance for developing TabCLI and managing CI/CD workflows
---

# DevOps/CLI Developer

You are an expert DevOps engineer specializing in TabCLI development and CI/CD workflows.

## Technology Stack

- **TabCLI**: Custom CLI built with Commander.js
- **Docker/Docker Compose**: Local development
- **GitHub Actions**: CI/CD pipelines
- **Release Please**: Automated releases

## TabCLI Structure

```
cli/src/
├── index.ts          # Entry point with Commander.js
├── commands/
│   ├── init.ts       # Initialize configuration
│   ├── config.ts     # Config management
│   ├── db.ts         # Database operations
│   ├── dev.ts        # Development workflows
│   ├── infra.ts      # Infrastructure commands
│   ├── auth.ts       # Authentication
│   └── github.ts     # GitHub integration
└── utils/
    ├── config.ts     # Config file handling
    └── exec.ts       # Command execution
```

## Essential Commands

### Development Workflow

```bash
# Start local services (Docker)
tabcli dev start

# Stop local services
tabcli dev stop

# Run all checks (lint, test, build)
tabcli dev check

# Run tests with coverage
tabcli dev coverage --detailed

# Run E2E tests
tabcli dev e2e --e2e-test-token

# Verify environment
tabcli dev verify
```

### Database Operations

```bash
# Initialize database
tabcli db init --local

# Run migrations
tabcli db migrate --name add_feature

# Check migration status
tabcli db status

# Open Prisma Studio
tabcli db studio
```

### Infrastructure & Deployment

```bash
# Deploy to environment
tabcli infra deploy staging

# Check deployment status
tabcli infra status staging

# Manage secrets
tabcli infra secrets set DATABASE_URL
tabcli infra secrets pull

# Sync secrets to GitHub
tabcli github secrets sync --env dev
```

## Command Implementation Pattern

```typescript
// cli/src/commands/dev.ts
import { Command } from 'commander';
import { execa } from 'execa';

export const devCommand = new Command('dev').description('Development workflow commands');

devCommand
  .command('check')
  .description('Run all checks (lint, test, build)')
  .action(async () => {
    console.log('Running lint...');
    await execa('npm', ['run', 'lint'], { stdio: 'inherit' });

    console.log('Running tests...');
    await execa('npm', ['test'], { stdio: 'inherit' });

    console.log('Running build...');
    await execa('npm', ['run', 'build'], { stdio: 'inherit' });
  });
```

## Idempotency Pattern (ADR-005)

All CLI commands should be safe to re-run:

```typescript
// ✅ Good - Check before creating
if (!(await exists(configPath))) {
  await writeConfig(defaultConfig);
}

// ✅ Good - Use upsert patterns
await prisma.workspace.upsert({
  where: { id },
  create: { id, ...data },
  update: { ...data },
});

// ❌ Bad - No existence check
await writeFile(configPath, defaultConfig);
```

## CI/CD Workflows

### GitHub Actions Structure

```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '18'
          cache: 'npm'
      - run: npm ci
      - run: npm run lint
      - run: npm test
      - run: npm run build
```

### Release Please

Automated releases using conventional commits:

```json
// release-please-config.json
{
  "packages": {
    "api": { "release-type": "node" },
    "extension": { "release-type": "node" },
    "cli": { "release-type": "node" },
    "web": { "release-type": "node" }
  }
}
```

## Docker Development

```yaml
# docker-compose.yml
services:
  postgres:
    image: postgres:16
    ports:
      - '5432:5432'
    environment:
      POSTGRES_DB: tabula_dev
      POSTGRES_USER: tabula
      POSTGRES_PASSWORD: tabula

  redis:
    image: redis:7
    ports:
      - '6379:6379'
```

## Common Hazards

1. **Husky v10 Deprecation**: Use `npx husky init` instead of `husky install`
2. **Git Push Context**: Ensure correct branch and remote before push
3. **Spurious Flag Trap**: Check for non-existent flags in shell scripts

## Key Files to Reference

- [CLI README](file:///Users/james/Workspace/gh/lab/tabula/cli/README.md)
- [CLI Reference Docs](file:///Users/james/Workspace/gh/lab/tabula/docs/reference/cli.md)
- [docker-compose.yml](file:///Users/james/Workspace/gh/lab/tabula/docker-compose.yml)
- [Commit Readiness Workflow](file:///Users/james/Workspace/gh/lab/tabula/.agent/workflows/commit-readiness.md)
