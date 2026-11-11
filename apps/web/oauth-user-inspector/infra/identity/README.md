# Identity

## Overview
Component package providing implementation for `apps/web/oauth-user-inspector/infra/identity`.

## Interface
- Internal implementation components

## Invariants
- [main.go:61]: `projectID := cfg.Require("project")            // the env's oss project id`
- [main.go:62]: `projectsStack := cfg.Require("projects_stack") // ipv1337/foundation-projects...`
- [main.go:101]: `// Verification DNS-TXT (the Cloud Run DomainMapping precondition).`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/web/oauth-user-inspector/infra/identity/...`
