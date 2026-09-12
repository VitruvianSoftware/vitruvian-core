# Architecture Decision Records (ADR)

This directory contains Architecture Decision Records (ADRs) for the Tabula project. ADRs document
important architectural decisions made during the development of the project.

## What is an ADR?

An Architecture Decision Record (ADR) is a document that captures an important architectural
decision made along with its context and consequences. ADRs help teams understand:

- Why certain technical choices were made
- What alternatives were considered
- What trade-offs were accepted
- What the expected outcomes are

## Index

| ADR                                        | Title                      | Status   | Date       |
| ------------------------------------------ | -------------------------- | -------- | ---------- |
| [001](001-technology-stack-selection.md) | Technology Stack Selection | Accepted | 2025-12-07 |
| [002](002-database-orm-selection.md)     | Database and ORM Selection | Accepted | 2025-12-07 |
| [003](003-testing-strategy.md)           | Testing Strategy           | Accepted | 2025-12-07 |
| [004](004-tabcli-platform-tool.md)       | TabCLI Platform Tool       | Accepted | 2025-12-07 |
| [005](005-cli-idempotency.md)            | TabCLI Command Idempotency | Accepted | 2025-12-08 |

## ADR Template

When creating a new ADR, use the following template:

```markdown
# ADR-XXX: [Title]

**Status:** [Proposed | Accepted | Deprecated | Superseded]  
**Date:** YYYY-MM-DD  
**Deciders:** [List of people involved in the decision]

## Context

[Describe the context and problem statement. What forces are at play?]

## Decision

[What is the change that we're proposing or have agreed to?]

## Consequences

### Positive

- [Benefit 1]
- [Benefit 2]

### Negative

- [Trade-off 1]
- [Trade-off 2]

### Neutral

- [Neutral consequence 1]

## Alternatives Considered

### Alternative 1: [Name]

[Description and why it was not chosen]

### Alternative 2: [Name]

[Description and why it was not chosen]

## References

- [Link to discussion]
- [Link to documentation]
```

## Creating a New ADR

1. Copy the template above
2. Number it sequentially (e.g., 004, 005)
3. Give it a descriptive title in kebab-case
4. Fill in all sections
5. Get it reviewed by the team
6. Update the index above

## Status Definitions

- **Proposed**: The ADR is proposed but not yet accepted
- **Accepted**: The ADR has been agreed upon and is active
- **Deprecated**: The decision is no longer relevant but kept for historical context
- **Superseded**: The decision has been replaced by a newer ADR (link to the new one)
