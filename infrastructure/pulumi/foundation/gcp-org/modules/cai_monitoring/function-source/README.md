# Function Source

## Overview
Component package providing implementation for `infrastructure/pulumi/foundation/gcp-org/modules/cai_monitoring/function-source`.

## Interface
- Internal implementation components

## Invariants
- [index.js:26]: `const uuid4 = require("uuid4");`
- [index.js:27]: `const moment = require("moment");`
- [index.js:30]: `const { SecurityCenterClient } = require("@google-cloud/security-center").v2;`

## Side Effects
- None

## Verification
- Run: `bazel test //infrastructure/pulumi/foundation/gcp-org/modules/cai_monitoring/function-source/...`
