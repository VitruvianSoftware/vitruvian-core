# ADR-004: TabCLI Platform Tool

**Status:** Accepted  
**Date:** 2025-12-07  
**Deciders:** Tabula Core Team

## Context

As Tabula's infrastructure grows, we need a unified way to handle operational tasks that Terraform
doesn't manage, such as:

- Managing runtime configuration across environments
- Handling secrets in Google Secret Manager
- Running database migrations and maintenance
- Deploying services to Cloud Run
- Performing operational workflows

Currently, we would need to create custom scripts for each task, which leads to:

- Inconsistent interfaces and patterns
- Poor discoverability of available operations
- Difficult maintenance and updates
- Lack of unified error handling and logging

We need a platform CLI tool similar to `gcloud` for GCP, but specifically for Tabula operations.

## Decision

We will create **TabCLI**, a comprehensive command-line interface tool for managing Tabula
infrastructure and operations.

**Technology Stack:**

- **Language:** TypeScript (consistency with rest of codebase)
- **CLI Framework:** Commander.js (robust, well-documented)
- **UI/UX:** Chalk (colors), Ora (spinners), Inquirer (prompts), Table (formatting)
- **Distribution:** npm workspace, can be installed globally via `npm link`

**Architecture:**

```
tabcli/
├── src/
│   ├── commands/        # Command implementations
│   │   ├── init.ts      # Initialize configuration
│   │   ├── config.ts    # Manage configuration
│   │   ├── db.ts        # Database operations
│   │   ├── secrets.ts   # Secrets management
│   │   ├── deploy.ts    # Deployment operations
│   │   └── version.ts   # Version information
│   ├── utils/           # Shared utilities
│   ├── types/           # TypeScript types
│   └── index.ts         # CLI entry point
└── README.md            # Documentation
```

**Command Structure:**

```
tabcli
├── init                 # Initialize configuration
├── config              # Configuration management
│   ├── list
│   ├── set <key> <value>
│   ├── get <key>
│   └── unset <key>
├── db                  # Database operations
│   ├── init
│   ├── migrate
│   ├── reset
│   ├── studio
│   └── status
├── secrets             # Secrets management
│   ├── set <key>
│   ├── get <key>
│   ├── list
│   └── delete <key>
├── deploy              # Deployment
│   ├── run [env]
│   ├── status [env]
│   └── logs [env]
└── version             # Version info
```

## Consequences

### Positive

1. **Unified Interface:**
   - Single tool for all operational tasks
   - Consistent command structure and patterns
   - Familiar `gcloud`-like experience

2. **Developer Productivity:**
   - Self-documenting with built-in help
   - Interactive prompts for complex operations
   - Clear error messages and feedback

3. **Maintainability:**
   - Centralized operational logic
   - Easy to add new commands
   - TypeScript type safety

4. **Discoverability:**
   - `tabcli --help` shows all available commands
   - Command-specific help with `tabcli <command> --help`
   - Examples in documentation

5. **Operational Excellence:**
   - Standardized deployment workflows
   - Secure secrets management
   - Database migration automation

### Negative

1. **Additional Dependency:**
   - Another tool to learn and maintain
   - Requires Node.js to be installed

2. **Learning Curve:**
   - Developers need to learn TabCLI commands
   - Mitigated: Similar to familiar tools like `gcloud`

3. **Maintenance Overhead:**
   - Need to keep commands updated as infrastructure evolves
   - Mitigated: Good documentation and tests

### Neutral

1. **Not a Replacement for:**
   - Terraform (infrastructure as code)
   - GitHub Actions (CI/CD)
   - Docker Compose (local development)

## Alternatives Considered

### Alternative 1: Custom Shell Scripts

**Pros:**

- Simple and straightforward
- No additional dependencies
- Easy to understand

**Cons:**

- No unified interface
- Difficult to discover available scripts
- Inconsistent error handling
- Hard to maintain
- No cross-platform support

**Why not chosen:** Lacks the structure and discoverability needed for a growing project.

### Alternative 2: Makefile

**Pros:**

- Simple and familiar
- Good for common tasks
- Cross-platform (with GNU Make)

**Cons:**

- Limited to simple commands
- No interactive prompts
- Poor error handling
- Not ideal for complex workflows
- Syntax can be confusing

**Why not chosen:** Too limited for complex operational workflows.

### Alternative 3: Use gcloud/terraform exclusively

**Pros:**

- Standard tools
- Well-documented
- No custom code

**Cons:**

- Terraform doesn't handle runtime operations well
- gcloud is generic, not Tabula-specific
- Need custom scripts anyway for workflows

**Why not chosen:** Doesn't address the need for Tabula-specific operations.

### Alternative 4: Skaffold

**Pros:**

- Continuous development workflow with file watching
- Supports Cloud Run deployments (in recent versions)
- Automated rebuilds and deploys on code changes
- Good for complex microservices architectures
- Built-in support for multiple deployment targets
- Strong community and Google backing

**Cons:**

- Additional abstraction layer on top of Docker Compose
- More complex configuration (skaffold.yaml + dockerfiles + k8s/cloudrun manifests)
- Steeper learning curve for team members
- Primarily designed for containerized applications (we have browser extension + API)
- Local development still uses Docker Compose under the hood
- Overkill for our current simple architecture (1 API service, 1 extension)

**Why not chosen:** While Skaffold does support Cloud Run and offers excellent continuous deployment
workflows, it adds complexity that isn't justified for our current architecture. Our setup consists
of:

- A single API service (Cloud Run)
- A browser extension (static build, no containerization)
- Local development needs (database, Redis)

For local development, Skaffold would still use Docker Compose underneath. For deployment, TabCLI
provides Cloud Run deployment with simpler configuration. If we evolve to a microservices
architecture with multiple containerized services requiring coordinated deployments, Skaffold would
be worth reconsidering.

## Implementation Details

### Configuration Storage

TabCLI stores configuration in `.tabula/config.json`:

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

This file is gitignored to prevent committing sensitive information.

### Secrets Management

Secrets are stored in Google Secret Manager using the gcloud CLI:

- Create/update: `gcloud secrets create/versions add`
- Retrieve: `gcloud secrets versions access latest`
- List: `gcloud secrets list`
- Delete: `gcloud secrets delete`

### Database Operations

Database commands wrap Prisma CLI:

- Migrations: `npx prisma migrate dev/deploy`
- Reset: `npx prisma migrate reset`
- Studio: `npx prisma studio`
- Status: `npx prisma migrate status`

### Deployment

Deployment uses `gcloud run deploy` for Cloud Run services and `npm run build` for extension
bundles.

## Docker Compose vs Skaffold

**Decision:** Continue using **Docker Compose** for local development.

**Rationale:**

While Skaffold does support Cloud Run deployments (as of recent versions) and offers excellent
continuous development workflows, Docker Compose is more appropriate for our current needs:

**Why Docker Compose:**

- **Simplicity:** Purpose-built for local development with minimal configuration
- **Current Architecture:** We have a simple setup (1 API service + 1 browser extension + local
  database/Redis)
- **Familiarity:** More developers are familiar with Docker Compose
- **Sufficient:** Meets all our local development needs without additional complexity
- **No Abstraction Overhead:** Direct control over container orchestration

**Skaffold Considerations:**

- Skaffold is excellent for continuous deployment and multi-service orchestration
- Recent versions do support Cloud Run (correcting earlier analysis)
- However, it adds an abstraction layer that isn't justified for our simple architecture
- For local development, Skaffold still uses Docker Compose underneath
- Better suited for teams with multiple containerized microservices

**When to Reconsider Skaffold:**

- We migrate to a microservices architecture with multiple containerized services
- We need coordinated deployments across multiple services
- We require advanced features like multi-stage builds with dependency management
- Team becomes proficient with container orchestration patterns

**Current Approach:**

- **Local Dev:** Docker Compose for database, Redis, and local services
- **Deployment:** TabCLI wraps gcloud commands for Cloud Run deployment
- **CI/CD:** GitHub Actions for automated deployments

This provides a simpler stack that's easier to understand, maintain, and debug while meeting all
current requirements.

## Migration Path

1. **Phase 1:** Create TabCLI with core commands (config, db, secrets)
2. **Phase 2:** Add deployment commands
3. **Phase 3:** Migrate existing scripts to TabCLI commands
4. **Phase 4:** Add team-specific commands as needed

## Success Criteria

- All operational tasks can be performed via TabCLI
- Developers can complete common workflows without custom scripts
- Clear documentation and help for all commands
- Type-safe command implementations
- Consistent error handling and user feedback

## References

- [Commander.js Documentation](https://github.com/tj/commander.js)
- [gcloud CLI Reference](https://cloud.google.com/sdk/gcloud/reference)
- [Inquirer.js Documentation](https://github.com/SBoudrias/Inquirer.js)
- [Google Secret Manager](https://cloud.google.com/secret-manager/docs)
