# Repo administration

Docs for administering the repo itself. Orientation:
[Repo admin quick start](../getting-started/repo-admin.md).

- [Copybara sync](copybara-sync.md) — the complete mirror-sync runbook: sync shapes
  per component, operations, failure modes, seeding new mirrors.
- [Merge automation](../../.github/workflows/README.md) — the merge queue and the
  auto-merge robots (release-please, Dependabot).
- [Claude Code cloud sessions](claude-code-cloud-sessions.md) — homelab k8s + SSH access
  wiring for that specific tool. Kept out of the vendor-neutral
  [`AGENTS.md`](../../AGENTS.md) on purpose; other agents need their own transport.
- Repo governance as code lives in
  [`infrastructure/pulumi/platform/repo_config`](../../infrastructure/pulumi/platform/repo_config/)
  — branch protection, required checks, environments, pipeline gates.
