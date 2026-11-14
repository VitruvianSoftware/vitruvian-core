---
description: Finalize all lint, format, and tests for commit
---

Address and fix all issues in this order:

1. `bazel test //apps/suites/vitruvian-tabs/...` (unit and hermetic integration tests)
2. `bazel test --config=e2e //apps/suites/vitruvian-tabs/...` (Playwright E2E when UI/sync/API behavior changed)
3. `bazel run //tools/format` (formatting)
