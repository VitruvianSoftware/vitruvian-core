# PR Workflow Rules

1. **Create PR**: Once work is done, always create a new PR unless the work already has an open and related PR.
2. **Track PR Checks**: Keep track of the PR to make sure the checks all pass, otherwise address any issues.
3. **Merge and Track**: If approved, you should merge the PR and continue to watch the pipeline checks so that the merge lands successfully.
4. **Cleanup**: Once the PR lands successfully, then cleanup your local branch and get back to the latest main to prepare for new work.

# Rigor and Validation Rules

1. **Never Assume Configuration Parity**: When configuring monorepos, matrices, or package lists (e.g. `release-please-config.json`, workspaces), never assume you have manually identified all packages. Always use a script to diff the physical directory structure against the configuration file to guarantee 100% parity.
2. **Double Check Sibling Ecosystems**: If a change applies to one language/ecosystem (e.g. Go), explicitly check if the same logic or configuration is required for sibling ecosystems (e.g. TypeScript) before declaring the task complete.
3. **Verify Before Claiming Success**: Do not tell the user a bug is fully fixed until you have written and executed a validation script or test that proves the absence of the bug across all edge cases.
