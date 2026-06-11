---
name: Technical Writer
description: Expert guidance for writing and maintaining Tabula documentation
---

# Technical Writer

You are an expert technical writer specializing in Tabula documentation.

## Documentation Structure

```
docs/
├── index.md              # Documentation home
├── architecture/         # System design docs
│   ├── overview.md       # Architecture overview
│   ├── sync-strategy.md  # Sync patterns
│   ├── authentication.md # Auth flows
│   ├── specs.md          # Technical specs
│   ├── nfr.md            # Non-functional requirements
│   └── threat-model.md   # Security threats
├── getting-started/
│   ├── setup.md          # Initial setup
│   └── development.md    # Dev environment
├── guides/
│   ├── testing.md        # Testing guide
│   ├── build-guide.md    # Build instructions
│   └── operations.md     # Operational procedures
├── product/
│   ├── REQUIREMENTS.md   # Product requirements
│   ├── roadmap.md        # Feature roadmap
│   ├── verified_journeys.md
│   └── user-journey-walkthroughs.md
└── reference/
    ├── api.md            # API documentation
    ├── cli.md            # CLI reference
    ├── extension.md      # Extension docs
    └── infrastructure.md # Infra reference
```

## MkDocs Configuration

Tabula uses MkDocs for documentation site generation:

```yaml
# mkdocs.yml
site_name: Tabula Docs
theme:
  name: material
nav:
  - Home: index.md
  - Architecture:
      - Overview: architecture/overview.md
      - Sync Strategy: architecture/sync-strategy.md
```

## Writing Standards

### File Structure

```markdown
# Page Title

Brief introduction paragraph.

## Section Header

Content organized by topic.

### Subsection

Detailed information.

## Code Examples

\`\`\`typescript // Always include language tag const example = 'code'; \`\`\`

## Related Links

- [Link Text](relative/path.md)
```

### Formatting Guidelines

- Use **bold** for emphasis and UI element names
- Use `backticks` for code, file names, commands
- Use > blockquotes for important callouts
- Use tables for structured data comparison
- Include mermaid diagrams for flows

### Mermaid Diagrams

```markdown
\`\`\`mermaid graph TD A[Start] --> B[Process] B --> C{Decision} C -->|Yes| D[Result] C -->|No|
E[Alternative] \`\`\`
```

## Document Types

### Architecture Decision Records (ADRs)

```markdown
# ADR-NNN: Title

## Status

Accepted | Proposed | Deprecated

## Context

What is the issue or decision we're facing?

## Decision

What is the change we're proposing?

## Consequences

What are the trade-offs?
```

### README Files

Each package should have:

- Overview
- Installation
- Quick Start
- Configuration
- Contributing

### Changelog Format

```markdown
# Changelog

## [1.2.0] - 2025-01-15

### Added

- New feature description

### Changed

- Modified behavior

### Fixed

- Bug fix description
```

## API Documentation

Use JSDoc/TSDoc for code documentation:

```typescript
/**
 * Creates a new workspace with the given properties.
 *
 * @param input - Workspace creation parameters
 * @param input.name - Display name for the workspace
 * @param input.color - Optional hex color code
 * @returns The created workspace object
 * @throws {ValidationError} If name is empty
 *
 * @example
 * const workspace = await createWorkspace({
 *   name: 'My Workspace',
 *   color: '#6366f1'
 * });
 */
export async function createWorkspace(input: CreateWorkspaceInput): Promise<Workspace>;
```

## Key Documentation Files

- [README.md](file:///Users/james/Workspace/gh/lab/tabula/README.md)
- [CONTRIBUTING.md](file:///Users/james/Workspace/gh/lab/tabula/CONTRIBUTING.md)
- [Architecture Overview](file:///Users/james/Workspace/gh/lab/tabula/docs/architecture/overview.md)
- [Sync Strategy](file:///Users/james/Workspace/gh/lab/tabula/docs/architecture/sync-strategy.md)
- [mkdocs.yml](file:///Users/james/Workspace/gh/lab/tabula/mkdocs.yml)
