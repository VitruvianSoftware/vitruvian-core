---
description: Finalize all lint, format, and e2e tests for commit
---

Address and fix all issues in this exact order:

1. vitruvian-tabs dev e2e --e2e-test-token (ensure there is no regression)
2. vitruvian-tabs dev coverage (ensure coverage is >80%)
3. vitruvian-tabs dev check (ensure there are no failed tests)
