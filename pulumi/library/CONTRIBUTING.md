# Contributing to Vitruvian Software Pulumi Library

Thank you for your interest in contributing!

## Development Setup

### Prerequisites

- [Go](https://go.dev/dl/) 1.21+
- [Pulumi CLI](https://www.pulumi.com/docs/install/) 3.0+
- [GNU Make](https://www.gnu.org/software/make/)

### Getting Started

```bash
git clone https://github.com/VitruvianSoftware/pulumi-library.git
cd pulumi-library

# Install dependencies
go mod tidy

# Build all packages
make build

# Run linter
make lint

# Run tests
make test
```

## Submitting Changes

1. **Fork** this repository.
2. **Create a feature branch** from `main`:
   ```bash
   git checkout -b feature/my-improvement
   ```
3. **Make your changes** and ensure all checks pass:
   ```bash
   make all  # runs: tidy, lint, build, test
   ```
4. **Commit** with a [conventional commit](https://www.conventionalcommits.org/) message:
   ```bash
   git commit -m "feat(iam): add support for TagValue IAM bindings"
   ```
5. **Push** and open a Pull Request against `main`.

## Code Style

### Go Conventions

- Follow [Effective Go](https://go.dev/doc/effective_go) conventions
- All exported types and functions **must** have doc comments
- Run `go fmt ./...` and `go vet ./...` before committing

### Design Rules

These rules are critical to the library's correctness:

1. **Plan-time values for dispatch fields.** Fields that control which GCP resource type to create (like `ParentType`) must be plain Go types (`string`, `[]string`), not `pulumi.StringInput`. This avoids the `ApplyT` anti-pattern. See the [Design Principles](./README.md#design-principles) section.

2. **Pulumi Inputs for GCP resource fields.** Fields that map to GCP resource arguments (like `ParentID`, `Role`, `Member`) should be `pulumi.StringInput` to accept outputs from other resources.

3. **Always return errors.** Never use `panic()` or `log.Fatal()`. All errors must be propagated to the caller.

4. **Single-file components.** Each package should be a single Go file until complexity demands splitting. Keep the public API surface minimal.

### File Headers

All Go files must include the Apache 2.0 license header:

```go
/*
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
```

### Adding a New Package

1. Create `pkg/<name>/<name>.go`
2. Define an `Args` struct, a component struct embedding `pulumi.ResourceState`, and a `New<Component>` constructor
3. Register as a `ComponentResource` with type `pkg:index:<Name>`
4. Create `pkg/<name>/README.md` following the pattern of existing package READMEs (Overview, API Reference, Examples, Resource Graph)
5. Add the package to the root README's package table
6. Update `go.mod` if new dependencies are needed

## CI Pipeline

The GitHub Actions CI pipeline (`.github/workflows/ci.yml`) runs on every push and PR to `main`:

1. `go mod tidy` — Ensures dependencies are clean (fails if `go.sum` changes)
2. `go vet ./...` — Static analysis
3. `go build ./...` — Compilation check
4. `go test -v ./...` — Unit tests

All checks must pass before a PR can be merged.

## Reporting Issues

Please open a [GitHub Issue](https://github.com/VitruvianSoftware/pulumi-library/issues/new) with:

- Which package is affected (`pkg/iam`, `pkg/project`, etc.)
- Steps to reproduce
- Expected vs. actual behavior
- Go version (`go version`) and Pulumi version (`pulumi version`)
