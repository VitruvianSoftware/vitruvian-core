# Repo administration

Docs for administering the repo itself. Orientation:
[Repo admin quick start](../getting-started/repo-admin.md).

- [Copybara sync](copybara-sync.md) — the complete mirror-sync runbook: sync shapes
  per component, operations, failure modes, seeding new mirrors.
- [Merge automation](../../.github/workflows/README.md) — the merge queue and the
  auto-merge robots (release-please, Dependabot).
- Repo governance as code lives in
  [`infrastructure/pulumi/platform/repo_config`](../../infrastructure/pulumi/platform/repo_config/)
  — branch protection, required checks, environments, pipeline gates.
