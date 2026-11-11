# Test

## Overview
Component package providing implementation for `packages/pulumi/examples/ts-foundation/test`.

## Interface
- `[clean_org.sh:script entrypoint]`
- `[disable_stacks.sh:script entrypoint]`
- `[mocks.ts:setupPulumiMocks]`
- `[restore_stacks.sh:script entrypoint]`
- `[setup_e2e.sh:script entrypoint]`
- `[validate_e2e.sh:script entrypoint]`
- `[validate_idempotency.sh:script entrypoint]`

## Invariants
- [0-bootstrap.config.test.ts:26]: `require(key: string): string {`
- [1-org.config.test.ts:24]: `require(key: string): string {`
- [2-environments.config.test.ts:54]: `it("should require all mandatory fields", () => {`
- [3-networks-hub-and-spoke.config.test.ts:16]: `it("should require environment code", () => {`
- [3-networks.config.test.ts:49]: `it("should require environment code", () => {`

## Side Effects
- [0-bootstrap.config.test.ts:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`
- [1-org.config.test.ts:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`
- [2-environments.config.test.ts:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`
- [3-networks-hub-and-spoke.config.test.ts:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`
- [3-networks.config.test.ts:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`
- [5-app-infra.config.test.ts:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`
- [clean_org.sh:9]: `#      http://www.apache.org/licenses/LICENSE-2.0`
- [clean_org.sh:133]: `folders=$(gcloud alpha resource-manager folders search --query="displayName:$...`
- [disable_stacks.sh:9]: `#      http://www.apache.org/licenses/LICENSE-2.0`
- [restore_stacks.sh:9]: `#      http://www.apache.org/licenses/LICENSE-2.0`

## Verification
- Run: `bazel test //packages/pulumi/examples/ts-foundation/test/...`
