---
trigger: always_on
description: After every code change
---

# Testing Policy

1. MANDATORY: Run the project's Bazel test suites after every code change (`bazel test //apps/suites/vitruvian-tabs/...`
   for unit and hermetic integration suites, and `bazel test --config=e2e //apps/suites/vitruvian-tabs/...` for Playwright E2E).
2. VERIFICATION: Do not rely on static analysis. You must receive a passing exit code from the
   terminal.
3. NO MOCKING: Do not mock the test results. If tests fail, fix the code and retry.
4. ARTIFACTS: Always include a snapshot of the passing test output in the final Walkthrough.
