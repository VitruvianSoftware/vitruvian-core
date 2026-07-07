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

Tabula is built with modern, scalable technologies within the VitruvianSoftware monorepo:

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

**Backend API:**

- Node.js with Fastify (TypeScript)
- Prisma ORM
- JWT authentication (RS256)
- Deployed on Google Cloud Run

**Database & Cache:**

- PostgreSQL 16
- Redis for cache/sessions
- Managed via K3s Homelab / CloudNativePG locally

**Infrastructure:**

- Google Cloud Platform (GCP)
- Pulumi for Infrastructure as Code (Workload Identity Federation)
- Cloud Run for serverless compute
- K3s Homelab over Tailscale for local development (`gitops/`)
- Bazel for monorepo builds and testing

## Getting Started

### Prerequisites

Before contributing, ensure you have:

- **Node.js** 22+
- **Bazel** (via `bazelisk`)
- **pnpm** (via Corepack or globally installed)
- **Docker** & **Tailscale** (for local K3s access)
- **Git** (version control)
- **gcloud CLI** (for GCP-related development)

### Fork and Clone

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/vitruvian-core.git
   cd vitruvian-core
   ```
3. Add the upstream repository:
   ```bash
   git remote add upstream https://github.com/VitruvianSoftware/vitruvian-core.git
   ```

### Set Up Development Environment

Tabula uses Bazel for building and testing, and a Tailscale-connected K3s cluster for its backend services.

1. Ensure your Tailscale is running and connected (required for homelab K3s access).
2. Set up the Bazel environment:
   ```bash
   bazel run //tools:bazel_env
   direnv allow
   ```

#### Building the Extension

```bash
# Build the extension via Bazel
bazel build //tabula/extension:extension
```

To run a continuous watch loop for extension development:
```bash
ibazel run //tabula/extension:dev
```

Load the extension in Chrome:
1. Navigate to `chrome://extensions/`
2. Enable "Developer mode"
3. Click "Load unpacked"
4. Select the output folder in `bazel-bin/tabula/extension/...`

#### Running the API Locally

```bash
# Start the API server via Bazel
ibazel run //tabula/api:dev
```

#### Running the Web Dashboard Locally

```bash
# Start the Web Dashboard via Bazel
ibazel run //tabula/web:dev
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

### Pulumi (Infrastructure as Code)

- Use Go for Pulumi programs
- Manage Workload Identity Federation instead of long-lived keys
- Store environment configs in `Pulumi.<env>.yaml`

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
# Run all tests in the repository
bazel test //...

# Run tests for a specific target
bazel test //tabula/api/...
bazel test //tabula/extension/...
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
