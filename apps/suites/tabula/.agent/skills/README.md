# Agent Skills

This directory contains comprehensive agent skills for AI agents working on the Tabula project.

## Available Skills

| Skill                                                                 | Purpose                     |
| --------------------------------------------------------------------- | --------------------------- |
| [Frontend Extension Developer](frontend-extension-developer/SKILL.md) | React, Zustand, Chrome APIs |
| [Backend API Developer](backend-api-developer/SKILL.md)               | Fastify, Prisma, JWT        |
| [Infrastructure Engineer](infrastructure-engineer/SKILL.md)           | Terraform, GCP, IaC         |
| [QA Engineer](qa-engineer/SKILL.md)                                   | Jest, Playwright, E2E       |
| [DevOps/CLI Developer](devops-cli-developer/SKILL.md)                 | TabCLI, CI/CD, Docker       |
| [Technical Writer](technical-writer/SKILL.md)                         | MkDocs, ADRs, changelogs    |
| [Security Analyst](security-analyst/SKILL.md)                         | JWT, CORS, CSP, threats     |

## Skill Format

Each skill follows YAML frontmatter + markdown format:

```yaml
---
name: Skill Name
description: Brief description for skill discovery
---
# Skill Name

Detailed instructions, patterns, commands, and key files.
```

## What Each Skill Includes

- **Technology stack** specific to the role
- **Project structure** and file organization
- **Code patterns** with examples
- **Commands** for common tasks
- **Common hazards** and their mitigations
- **Key files** with direct links to source

## Usage

Agents should read relevant SKILL.md files when:

- Starting work on a specific component
- Debugging issues in that area
- Following established patterns
- Running verification workflows
