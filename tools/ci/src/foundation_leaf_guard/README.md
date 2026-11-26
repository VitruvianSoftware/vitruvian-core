# Foundation Leaf Guard

## Overview
The first job of `foundation-proj-deploy.yaml` and `foundation-app-deploy.yaml`.
It refuses a deploy whose `working-directory`, `business-unit` or `environment`
names anything other than one of that stage's own leaves (#4279). Those inputs
are free strings, and the development and nonproduction Environments have no
required reviewer, so this check has to live in the workflow itself, not only in
`//tools/agent-app workflow-run`.

Accepted, and nothing else:
- `working-directory`: exactly `infrastructure/pulumi/foundation/<stage>`;
- `business-unit`: `business_unit_<n>`;
- `environment`: `shared`, `development`, `nonproduction` or `production`;
- and `<stage root>/<business-unit>/<environment>/Pulumi.yaml` must be a regular file.

## Interface
- `[lib.rs:refusal]`
- `[lib.rs:business_unit_ok]`
- `[lib.rs:run]`: `foundation_leaf_guard <stage> <working-directory> <business-unit> <environment>`, from the checkout root.

## Side Effects
- None. It prints `::error::` and exits 1, or prints OK and exits 0.

## Verification
- Run: `bazel test //tools/ci:foundation_leaf_guard_lib_test //tools/ci:foundation_leaf_guard_test`
