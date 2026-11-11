# Nonproduction

## Overview
Component package providing implementation for `infrastructure/pulumi/foundation/gcp-app-infra/business_unit_1/nonproduction`.

## Interface
- `[config.go:AppInfraConfig]`
- `[config.go:AppConfig]`

## Invariants
- [config.go:64]: `ProjectsStackName: cfg.Require("projects_stack_name"),`

## Side Effects
- None

## Verification
- Run: `bazel test //infrastructure/pulumi/foundation/gcp-app-infra/business_unit_1/nonproduction/...`
