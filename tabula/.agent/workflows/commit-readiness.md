---
description: Finalize all lint, format, and e2e tests for commit
---

Address and fix all issues in this exact order:

1. tabcli dev e2e --e2e-test-token (ensure there is no regression)
2. tabcli dev coverage (ensure coverage is >80%)
3. tabcli dev check (ensure there are no failed tests)
