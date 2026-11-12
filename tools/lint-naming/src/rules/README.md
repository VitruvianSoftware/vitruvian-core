# Rules

## Overview
Component package providing implementation for `tools/lint-naming/src/rules`.

## Interface
- `[bazel.rs:BINARY_RULE_TYPES]`
- `[bazel.rs:is_kebab_target]`
- `[bazel.rs:is_snake_target]`
- `[bazel.rs:is_shell_test_target]`
- `[bazel.rs:is_starlark_file]`
- `[bazel.rs:validate_starlark_file_name]`
- `[bazel.rs:validate_bazel_target_name]`
- `[bazel.rs:BuildFileResult]`
- `[bazel.rs:validate_build_file_content]`
- `[bazel.rs:fallback_scan]`
- `[configs.rs:is_workflow_file_base]`
- `[configs.rs:is_pulumi_config_key]`
- `[configs.rs:is_rfc1123]`
- `[configs.rs:validate_config_file_name]`
- `[configs.rs:validate_workflow_yaml_content]`
- `[configs.rs:validate_k8s_resource_name]`
- `[configs.rs:validate_pulumi_config_key]`
- `[directories.rs:ALLOWED_DOT_DIRS]`
- `[directories.rs:GO_PACKAGE_DIR_ROOTS]`
- `[directories.rs:SWIFT_DIR_ROOTS]`
- `[retired_names.rs:RULE_ID]`
- `[retired_names.rs:is_allowlisted_path]`
- `[retired_names.rs:validate_retired_path]`
- `[retired_names.rs:validate_retired_content]`
- `[retired_names.rs:validate_retired_file_bytes]`

## Invariants
- [bazel.rs:342]: `assert!(validate_bazel_target_name("B", "agent-app_test", "sh_test", None).is...`
- [bazel.rs:343]: `assert!(validate_bazel_target_name("B", "app.min", "js_binary", None).is_empt...`
- [bazel.rs:344]: `assert!(`
- [configs.rs:312]: `assert!(wf("jobs:\n  unit-test:\n    runs-on: x\n").is_empty());`
- [configs.rs:317]: `assert!(wf("jobs:\n  b:\n    steps:\n      - id: ${{ matrix.step_id }}\n").is...`
- [configs.rs:331]: `assert!(wf(content).is_empty());`
- [directories.rs:224]: `assert!(validate_directory_name("tools/ci-preflight", false).is_empty());`
- [directories.rs:231]: `assert!(validate_directory_name("a", true).is_empty());`
- [directories.rs:232]: `assert!(validate_directory_name("", false).is_empty());`
- [environment.rs:108]: `assert!(validate_env_var_name("x.sh", "GH_TOKEN", None).is_empty());`

## Side Effects
- [directories.rs:246]: `"tabula/web/prisma/migrations/20260524120000_init_schema",`
- [migration.rs:51]: `"tabula/web/prisma",`

## Verification
- Run: `bazel test //tools/lint-naming/src/rules/...`
