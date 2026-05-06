# Contributing

Thank you for your interest in contributing to the Pulumi Example Foundation (TypeScript)!

## Development Workflow

This repository follows a **trunk-based development** workflow. For guidance
on how changes flow through environments, refer to the upstream
[Google Terraform Example Foundation](https://github.com/terraform-google-modules/terraform-example-foundation)
for the reference architecture and branching strategy context.

### Branch Structure

The branching model varies by stage:

| Stage | Branches | Rationale |
|-------|----------|-----------|
| `0-bootstrap` | `production` | Shared infrastructure — single environment |
| `1-org` | `production` | Organization-wide resources — single environment |
| `2-environments` | `development`, `nonproduction`, `production` | Per-environment resources |
| `3-networks-svpc` | `development`, `nonproduction`, `production` | Per-environment networks |
| `3-networks-hub-and-spoke` | `development`, `nonproduction`, `production` | Per-environment networks |
| `4-projects` | `development`, `nonproduction`, `production` | Per-environment projects |
| `5-app-infra` | `development`, `nonproduction`, `production` | Per-environment app infra |

### Submitting Changes

1. Fork this repository.
2. Create a feature branch from `main`.
3. Make your changes and ensure they pass `npx tsc --noEmit` locally.
4. Open a Pull Request against the `main` branch.
5. The CI pipeline will validate your changes.
6. Once approved and merged, changes are available for consumption.

### Code Style

- **TypeScript**: Follow [TypeScript best practices](https://www.typescriptlang.org/docs/handbook/) and strict mode conventions.
- **Naming**: Use camelCase for variables and functions, PascalCase for classes and interfaces.
- **Comments**: All exported classes and functions should have JSDoc comments.
- **Error handling**: Use Pulumi's `Output` type and handle errors gracefully.
- **Naming conventions**: Follow the [naming conventions](https://cloud.google.com/architecture/security-foundations/using-example-terraform#naming_conventions) from the Security Foundations Guide.

### Shared Library

Reusable components live in the separate
[pulumi-library](https://github.com/VitruvianSoftware/pulumi-library)
repository. If your change involves a new reusable pattern, consider whether
it belongs in the library rather than in this foundation repo.

### Testing

- Run `npx tsc --noEmit` to validate TypeScript compilation for any stage you modify.
- Run `pulumi preview` to validate your changes before submitting.
- Ensure all stages compile independently.

## Reporting Issues

Please open a GitHub Issue with:
- Which stage is affected
- Steps to reproduce
- Expected vs. actual behavior
- Relevant Pulumi/Node.js version information
