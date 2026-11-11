# Production

## Overview
Component package providing implementation for `infrastructure/pulumi/foundation/gcp-app-infra/business_unit_2/production`.

## Interface
- `[config.go:AppInfraConfig]`
- `[config.go:AppConfig]`

## Invariants
- [config.go:62]: `ProjectsStackName: cfg.Require("projects_stack_name"),`

## Side Effects
- None

## Verification
- Run: `bazel test //infrastructure/pulumi/foundation/gcp-app-infra/business_unit_2/production/...`
