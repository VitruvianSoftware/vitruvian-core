---
trigger: always_on
description: After every code change
---

# Testing Policy

1. MANDATORY: You must execute the project's test suite (e.g., `tabcli dev e2e --e2e-test-token`,
   `tabcli dev coverage`, `tabcli dev check`) after every code change.
2. VERIFICATION: Do not rely on static analysis. You must receive a passing exit code from the
   terminal.
3. NO MOCKING: Do not mock the test results. If tests fail, fix the code and retry.
4. ARTIFACTS: Always include a snapshot of the passing test output in the final Walkthrough.
