# Org Folders

## Overview
Component package providing implementation for `infrastructure/pulumi/foundation/org-folders`.

## Interface
- Internal implementation components

## Invariants
- [main.go:44]: `orgID := conf.Require("org_id")`
- [main.go:93]: `billingAccount := conf.Require("billing_account")`

## Side Effects
- None

## Verification
- Run: `bazel test //infrastructure/pulumi/foundation/org-folders/...`
