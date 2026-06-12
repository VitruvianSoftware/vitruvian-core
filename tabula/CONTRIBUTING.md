# Contributing to Tabula

Thank you for your interest in contributing to Tabula! We welcome contributions from the community
and are grateful for your support.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Pull Request Process](#pull-request-process)
- [Coding Standards](#coding-standards)
- [Project Structure](#project-structure)
- [Testing Guidelines](#testing-guidelines)
- [Documentation](#documentation)
- [Community](#community)

## Code of Conduct

### Our Pledge

We are committed to providing a welcoming and inclusive environment for everyone. We expect all
contributors to:

- Be respectful and considerate
- Welcome newcomers and help them get started
- Be open to constructive feedback
- Focus on what's best for the project and community
- Show empathy towards other community members

### Unacceptable Behavior

- Harassment, discrimination, or offensive comments
- Trolling, insulting, or derogatory remarks
- Publishing others' private information
- Any conduct that would be inappropriate in a professional setting

## Tech Stack

Tabula is built with modern, scalable technologies:

**Browser Extension:**

- TypeScript with strict mode
- Manifest V3 (Chrome Extensions API)
- React 18 for popup UI
- Zustand for state management
- Chrome Extension APIs: `tabs`, `storage`, `identity`, `alarms`, `scripting`

**Frontend (Web Dashboard):**

- Next.js 14 (App Router)
- React 18
- TypeScript (strict mode)
- Tailwind CSS for styling
- Deployed on Cloudflare Pages or Vercel

**Backend API:**

- **Option 1**: Go with Gin framework (preferred for performance)
- **Option 2**: Node.js with Fastify
- JWT authentication (RS256)
- Deployed on Google Cloud Run

**Database:**

- PostgreSQL 16 on Neon (serverless)
- Migrations with golang-migrate or Prisma
- Connection pooling via PgBouncer

**Cache & Sync:**

- Upstash Redis (serverless, edge caching)
- REST API for cache access
- Used for sessions, sync state, rate limiting

**Infrastructure:**

- Google Cloud Platform (GCP)
- Terraform for Infrastructure as Code
- Cloud Run for serverless compute
- Cloud Storage for backups and assets
- Cloud Scheduler for cron jobs
- Pub/Sub for event-driven architecture
- Google Secret Manager for secrets storage

**Authentication (Phase 4):**

- WorkOS for SSO and SCIM
- Email/password with JWT (Phase 1-3)

## Getting Started

### Prerequisites

Before contributing, ensure you have:

- **Node.js** 18+ (for extension and web dashboard)
- **Go** 1.21+ (for backend API) or Node.js 18+
- **Docker** (for local development)
- **Git** (version control)
- **Terraform** 1.6+ (for infrastructure changes)
- **gcloud CLI** (for GCP-related development)
- **PostgreSQL** client (psql) for database operations

### Fork and Clone

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/tabula.git
   cd tabula
   ```
3. Add the upstream repository:
   ```bash
   git remote add upstream https://github.com/VitruvianSoftware/vitruvian-core.git
   ```

### Set Up Development Environment

#### Infrastructure Setup (Optional)

For backend/infrastructure development:

```bash
cd infrastructure/environments/dev
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your GCP project and settings
terraform init
terraform apply
```

See [Infrastructure README](./infrastructure/README.md) for detailed setup.

### Extension Development

See the [Build Guide](./docs/guides/build-guide.md) for detailed instructions on building for
different environments.

```bash
cd extension
npm install
npm run dev        # Start development build with watch mode
npm run build      # Production build (defaults to API_URL=http://localhost:8080/api/v1)
npm run test       # Run tests
```

Load the extension in Chrome:

1. Navigate to `chrome://extensions/`
2. Enable "Developer mode"
3. Click "Load unpacked"
4. Select the `extension/dist` folder

#### API Development (Go)

```bash
cd api
go mod download
go run cmd/api/main.go        # Start development server
go test ./...                  # Run tests
golangci-lint run              # Run linter
```

#### API Development (Node.js Alternative)

```bash
cd api
npm install
npm run dev        # Start development server with hot reload
npm run test       # Run tests
npm run lint       # Run ESLint
```

#### Web Dashboard Development

```bash
cd dashboard
npm install
npm run dev        # Start Next.js development server (http://localhost:3000)
npm run build      # Production build
npm run test       # Run tests
npm run lint       # Run ESLint
```

## Development Workflow

### 1. Create a Branch

Always create a new branch for your work:

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/bug-description
```

**Branch Naming Conventions:**

- `feature/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation changes
- `refactor/` - Code refactoring
- `test/` - Test additions or changes
- `chore/` - Maintenance tasks

### 2. Make Your Changes

- Write clean, readable code
- Follow the project's coding standards
- Add tests for new functionality
- Update documentation as needed
- Keep commits small and focused

### 3. Commit Your Changes

Write clear, descriptive commit messages:

```bash
git add .
git commit -m "feat: add workspace search functionality"
```

**Commit Message Format:**

```
<type>: <short description>

<optional longer description>

<optional footer>
```

**Types:**

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Test changes
- `chore`: Build/tooling changes

**Examples:**

```
feat: add cross-device sync for workspaces

- Implement Pub/Sub integration
- Add sync conflict resolution
- Update API endpoints for sync

Closes #123
```

### 4. Keep Your Branch Updated

Regularly sync with the upstream repository:

```bash
git fetch upstream
git rebase upstream/main
```

If there are conflicts, resolve them and continue:

```bash
git add .
git rebase --continue
```

### 5. Push Your Changes

```bash
git push origin feature/your-feature-name
```

## Pull Request Process

### Before Submitting

- [ ] Code follows the project's style guidelines
- [ ] All tests pass
- [ ] New tests added for new functionality
- [ ] Documentation updated
- [ ] Commits are clean and well-described
- [ ] Branch is up to date with main

### Submitting a PR

1. Go to the [Tabula repository](https://github.com/VitruvianSoftware/vitruvian-core)
2. Click "New Pull Request"
3. Select your branch
4. Fill out the PR template:

```markdown
## Description

Brief description of changes

## Type of Change

- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Refactoring
- [ ] Other (describe)

## Testing

How has this been tested?

## Screenshots (if applicable)

Add screenshots for UI changes

## Checklist

- [ ] Code follows style guidelines
- [ ] Tests pass
- [ ] Documentation updated
- [ ] No breaking changes (or documented)
```

### Review Process

1. **Automated Checks**: CI/CD pipeline runs tests and linters
2. **Code Review**: Maintainers review your code
3. **Feedback**: Address any requested changes
4. **Approval**: Once approved, your PR will be merged

**Response Times:**

- Initial review: Within 2-3 business days
- Follow-up reviews: Within 1-2 business days

## Coding Standards

### General Principles

- **DRY**: Don't Repeat Yourself
- **KISS**: Keep It Simple, Stupid
- **YAGNI**: You Aren't Gonna Need It
- **Single Responsibility**: Each function/module should do one thing well
- **Separation of Concerns**: Keep business logic separate from presentation

### JavaScript/TypeScript

**Configuration:**

- TypeScript strict mode enabled (`strict: true` in tsconfig.json)
- ESLint with recommended + Airbnb config
- Prettier for code formatting (single quotes, no semicolons)
- Pre-commit hooks enforce formatting

**Code Style:**

- Use TypeScript for type safety (no `any` types)
- Follow [Airbnb JavaScript Style Guide](https://github.com/airbnb/javascript)
- Prefer functional programming patterns
- Use async/await over promises
- Explicit return types for all functions
- Meaningful variable and function names

**Example:**

```typescript
// Good
interface CreateWorkspaceParams {
  name: string;
  description?: string;
  color?: string;
}

async function createWorkspace(params: CreateWorkspaceParams): Promise<Workspace> {
  const response = await api.post('/workspaces', params);
  return response.data;
}

// Avoid
function createWorkspace(params: any) {
  return api.post('/workspaces', params).then((res) => res.data);
}
```

**TypeScript Rules:**

- No `any` types (use `unknown` or specific types)
- All functions have explicit return types
- Interfaces for object shapes, types for unions/primitives
- Use nullish coalescing (`??`) and optional chaining (`?.`)
- Prefer `const` over `let`, never use `var`

### Go

**Configuration:**

- Go 1.21+ with modules
- `gofmt` for formatting (automatic)
- `golangci-lint` for linting
- Pre-commit hooks enforce formatting

**Code Style:**

- Follow [Effective Go](https://golang.org/doc/effective_go.html)
- Write idiomatic Go code
- Add GoDoc comments for exported functions
- Use standard library where possible
- Error wrapping with `%w` (Go 1.13+)

**Example:**

```go
// GetWorkspaces retrieves all workspaces for a user.
// Returns an error if the database query fails.
func GetWorkspaces(ctx context.Context, userID string) ([]Workspace, error) {
    var workspaces []Workspace

    err := db.WithContext(ctx).
        Where("user_id = ?", userID).
        Order("position ASC").
        Find(&workspaces).Error
    if err != nil {
        return nil, fmt.Errorf("failed to fetch workspaces: %w", err)
    }

    return workspaces, nil
}
```

**Go Best Practices:**

- Always handle errors (don't ignore them)
- Use context for cancellation and timeouts
- Close resources with `defer`
- Keep functions small and focused
- Package names are lowercase, single word

### Terraform

- Use modules for reusability
- Add descriptions to all variables and outputs
- Use meaningful resource names
- Mark sensitive outputs appropriately

**Example:**

```hcl
variable "project_id" {
  description = "GCP project ID"
  type        = string
}

output "api_url" {
  description = "Cloud Run API URL"
  value       = google_cloud_run_v2_service.api.uri
}
```

### React/Next.js

- Use functional components with hooks
- Follow [React best practices](https://react.dev/learn)
- Use TypeScript interfaces for props
- Organize by feature, not file type

**Example:**

```typescript
interface WorkspaceCardProps {
  workspace: Workspace;
  onSelect: (id: string) => void;
}

export function WorkspaceCard({ workspace, onSelect }: WorkspaceCardProps) {
  return (
    <div onClick={() => onSelect(workspace.id)}>
      <h3>{workspace.name}</h3>
    </div>
  );
}
```

## Project Structure

```
tabula/
├── extension/              # Browser extension (Chrome/Edge/Firefox)
│   ├── src/
│   │   ├── background/    # Service worker
│   │   │   ├── index.ts          # Main background script
│   │   │   ├── tab-manager.ts    # Tab lifecycle management
│   │   │   ├── sync-engine.ts    # Sync with backend
│   │   │   └── storage-manager.ts # Local storage operations
│   │   ├── popup/         # Popup UI (React)
│   │   │   ├── App.tsx           # Main popup component
│   │   │   ├── components/       # React components
│   │   │   ├── state/            # Zustand stores
│   │   │   ├── hooks/            # Custom React hooks
│   │   │   └── index.tsx         # Entry point
│   │   ├── content/       # Content scripts
│   │   │   └── index.ts          # Tab suspension logic
│   │   ├── shared/        # Shared utilities
│   │   │   ├── api/              # API client
│   │   │   ├── constants.ts      # Constants
│   │   │   └── utils.ts          # Helper functions
│   │   └── types/         # TypeScript types
│   │       ├── workspace.ts
│   │       ├── tab.ts
│   │       └── index.ts
│   ├── public/            # Static assets
│   │   ├── icons/
│   │   └── popup.html
│   ├── manifest.json      # Extension manifest
│   ├── package.json
│   ├── tsconfig.json
│   └── webpack.config.js
│
├── api/                   # Backend API
│   ├── cmd/               # Entry points
│   │   └── api/
│   │       └── main.go    # Main application entry
│   ├── internal/          # Internal packages (Go)
│   │   ├── handlers/      # HTTP request handlers
│   │   │   ├── auth.go
│   │   │   ├── workspace.go
│   │   │   ├── tab.go
│   │   │   └── sync.go
│   │   ├── services/      # Business logic
│   │   │   ├── auth.go
│   │   │   ├── workspace.go
│   │   │   └── sync.go
│   │   ├── models/        # Data models
│   │   │   ├── user.go
│   │   │   ├── workspace.go
│   │   │   └── tab.go
│   │   ├── middleware/    # HTTP middleware
│   │   │   ├── auth.go
│   │   │   ├── cors.go
│   │   │   └── ratelimit.go
│   │   ├── database/      # Database connection
│   │   │   └── postgres.go
│   │   └── cache/         # Cache connection
│   │       └── redis.go
│   ├── pkg/               # Public packages
│   │   └── jwt/           # JWT utilities
│   ├── migrations/        # Database migrations
│   │   ├── 000001_create_users.up.sql
│   │   ├── 000001_create_users.down.sql
│   │   └── ...
│   ├── go.mod
│   ├── go.sum
│   ├── Dockerfile
│   └── openapi.yaml       # OpenAPI 3.0 specification
│
├── dashboard/             # Web dashboard (Next.js)
│   ├── app/               # App router pages
│   │   ├── layout.tsx
│   │   ├── page.tsx
│   │   ├── workspaces/
│   │   ├── settings/
│   │   └── api/           # API routes
│   ├── components/        # React components
│   │   ├── ui/            # UI components
│   │   ├── workspace/     # Workspace components
│   │   └── layout/        # Layout components
│   ├── lib/               # Utilities
│   │   ├── api.ts         # API client
│   │   ├── auth.ts        # Auth utilities
│   │   └── utils.ts       # Helper functions
│   ├── styles/            # Global styles
│   ├── public/            # Static assets
│   ├── package.json
│   ├── tsconfig.json
│   ├── tailwind.config.js
│   └── next.config.js
│
├── infrastructure/        # Terraform IaC
│   ├── modules/           # Reusable Terraform modules
│   │   ├── cloud-run/
│   │   ├── database/
│   │   ├── storage/
│   │   └── scheduler/
│   ├── environments/      # Environment-specific configs
│   │   ├── dev/
│   │   ├── staging/
│   │   └── prod/
│   └── README.md
│
├── docs/                  # Documentation
│   ├── architecture/      # Architecture docs (overview, specs, NFRs)
│   ├── getting-started/   # Setup and development guides
│   ├── guides/            # How-to guides (testing, etc.)
│   ├── product/           # Product docs (roadmap, user stories)
│   └── reference/         # Reference docs (CLI, infrastructure)
│
├── scripts/               # Build and deployment scripts
│   ├── build.sh           # Build all components
│   ├── deploy.sh          # Deploy to GCP
│   └── test.sh            # Run all tests
│
├── .github/               # GitHub configuration
│   ├── workflows/         # GitHub Actions
│   │   ├── ci.yml
│   │   ├── deploy.yml
│   │   └── test.yml
│   └── ISSUE_TEMPLATE/    # Issue templates
│       ├── feature_request.md
│       └── bug_report.md
│
├── .gitignore
├── README.md
├── CONTRIBUTING.md
└── LICENSE
```

## Testing Guidelines

### Unit Tests

- Write tests for all new functionality
- Aim for >80% code coverage
- Use descriptive test names

**JavaScript/TypeScript:**

```typescript
describe('WorkspaceService', () => {
  it('should create a new workspace', async () => {
    const workspace = await workspaceService.create({
      name: 'Test Workspace',
      userId: 'user-123',
    });
    expect(workspace.name).toBe('Test Workspace');
  });
});
```

**Go:**

```go
func TestCreateWorkspace(t *testing.T) {
    workspace, err := CreateWorkspace(ctx, "Test Workspace", "user-123")
    assert.NoError(t, err)
    assert.Equal(t, "Test Workspace", workspace.Name)
}
```

### Integration Tests

- Test API endpoints end-to-end
- Use test databases
- Clean up after tests

### Running Tests

```bash
# Extension
cd extension && npm test

# API (Node.js)
cd api && npm test

# API (Go)
cd api && go test ./...

# Web
cd web && npm test
```

## Documentation

### Code Documentation

- Add JSDoc/GoDoc comments for public APIs
- Explain complex logic with inline comments
- Keep comments up to date with code changes

### Documentation Updates

When changing functionality:

1. Update relevant docs in `/docs`
2. Update README if user-facing changes
3. Update architecture diagrams if needed
4. Add migration guides for breaking changes

### Writing Documentation

- Use clear, concise language
- Include code examples
- Add diagrams where helpful
- Keep formatting consistent

## Community

### Getting Help

- **Documentation**: Check [/docs](./docs) first
- **GitHub Issues**: Search existing issues
- **Discussions**: Ask questions in
  [GitHub Discussions](https://github.com/VitruvianSoftware/vitruvian-core/discussions)

### Reporting Bugs

Use the bug report template and include:

- Steps to reproduce
- Expected behavior
- Actual behavior
- Screenshots (if applicable)
- Environment details (browser, OS, version)

### Suggesting Features

Use the feature request template and include:

- Problem you're trying to solve
- Proposed solution
- Alternative solutions considered
- Additional context

### Communication Channels

- **GitHub Issues**: Bug reports and feature requests
- **GitHub Discussions**: Questions and community discussion
- **Pull Requests**: Code contributions and reviews

## Recognition

Contributors will be:

- Listed in the project contributors
- Credited in release notes
- Mentioned in documentation (for significant contributions)

## Questions?

If you have questions about contributing, feel free to:

- Open a [Discussion](https://github.com/VitruvianSoftware/vitruvian-core/discussions)
- Reach out to maintainers
- Check the [documentation](./docs)

---

**Thank you for contributing to Tabula! 🎉**
