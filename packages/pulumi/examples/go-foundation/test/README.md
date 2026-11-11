# Test

## Overview
Component package providing implementation for `packages/pulumi/examples/go-foundation/test`.

## Interface
- `[clean_org.sh:script entrypoint]`
- `[disable_stacks.sh:script entrypoint]`
- `[restore_stacks.sh:script entrypoint]`
- `[setup_e2e.sh:script entrypoint]`
- `[validate_e2e.sh:script entrypoint]`
- `[validate_idempotency.sh:script entrypoint]`

## Invariants
- None

## Side Effects
- [clean_org.sh:9]: `#      http://www.apache.org/licenses/LICENSE-2.0`
- [clean_org.sh:136]: `folders=$(gcloud alpha resource-manager folders search --query="displayName:$...`
- [disable_stacks.sh:9]: `#      http://www.apache.org/licenses/LICENSE-2.0`
- [restore_stacks.sh:9]: `#      http://www.apache.org/licenses/LICENSE-2.0`
- [setup_e2e.sh:9]: `#      http://www.apache.org/licenses/LICENSE-2.0`
- [validate_e2e.sh:9]: `#      http://www.apache.org/licenses/LICENSE-2.0`

## Verification
- Run: `bazel test //packages/pulumi/examples/go-foundation/test/...`
