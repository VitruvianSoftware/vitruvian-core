# Src

## Overview
Component package providing implementation for `packages/pulumi/examples/src`.

## Interface
- `[lib.rs:DEPLOY_STAGES]`
- `[lib.rs:ALL_STAGES]`
- `[lib.rs:REVERSE_CLEAN_STAGES]`
- `[lib.rs:REQUIRED_ROLES]`
- `[lib.rs:REQUIRED_APIS]`
- `[lib.rs:PROJECT_PREFIXES]`
- `[lib.rs:SA_CONSTRUCTOR_PREFIXES]`
- `[lib.rs:Flavor]`
- `[lib.rs:parse_dotenv]`
- `[lib.rs:load_dotenv_from_dir]`
- `[lib.rs:DeployOptions]`
- `[lib.rs:parse_deploy_args]`
- `[lib.rs:deploy_help_text]`
- `[lib.rs:order_stages]`
- `[lib.rs:extract_stack_name_from_filename]`
- `[lib.rs:find_stacks]`
- `[lib.rs:order_stack_targets]`
- `[lib.rs:run_deploy]`
- `[lib.rs:ValidateReqOptions]`
- `[lib.rs:parse_validate_req_args]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //packages/pulumi/examples/src/...`
