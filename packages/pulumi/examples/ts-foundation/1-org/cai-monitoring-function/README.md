# Cai Monitoring Function

## Overview
Component package providing implementation for `packages/pulumi/examples/ts-foundation/1-org/cai-monitoring-function`.

## Interface
- Internal implementation components

## Invariants
- [index.js:20]: `const uuid4 = require("uuid4");`
- [index.js:21]: `const moment = require("moment");`
- [index.js:24]: `const { SecurityCenterClient } = require("@google-cloud/security-center").v2;`

## Side Effects
- [index.js:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`

## Verification
- Run: `bazel test //packages/pulumi/examples/ts-foundation/1-org/cai-monitoring-function/...`
