## Summary
<!-- Brief description of what this PR accomplishes and why -->

## Motivation & Context
<!-- Link to any relevant issue or explain the driving requirement -->

## Affected Units / Components
<!-- Check all affected components -->
- [ ] `apps/cli/devx`
- [ ] `apps/cli/homelab`
- [ ] `apps/suites/tabula`
- [ ] `apps/mcp/slack`
- [ ] `apps/desktop/nexus-agent`
- [ ] `apps/web/oauth-user-inspector`
- [ ] `apps/web/backstage`
- [ ] `infrastructure/pulumi`
- [ ] `gitops/argocd`
- [ ] `tools/platform`
- [ ] Documentation / Metadata only

## Verification & Evidence
<!-- Paste terminal output or test commands proving the change works and does not break invariants -->
- Verification command(s) executed:
  - `bazel test ...`
  - `bazel run //tools/conformance:check`
  - `bazel run //tools/license:check`
- Results:

## Pre-Submission Checklist
<!-- Verify all items before opening the pull request -->
- [ ] Authored under designated identity (agent GitHub App via `eval "$(bazel run //tools/agent-app -- env <agent>)"` or human)
- [ ] Executed inside an isolated worktree (`bazel run //tools/worktree -- <branch>`)
- [ ] License headers verified (`bazel run //tools/license:check`)
- [ ] Naming standards verified (`bazel test //tools/lint-naming/...`)
- [ ] Conformance checks pass (`bazel run //tools/conformance:check`)
- [ ] No secrets, tokens, or credentials committed
