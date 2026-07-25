# Archive — point-in-time artifacts

Everything under this directory is a **historical record**: completed plans, approved
designs whose work has shipped, audits, assessments, and cutover narratives. They are
kept for provenance and archaeology — **do not treat them as current guidance**, even
where they haven't been formally superseded. Current guidance lives in
[`docs/README.md`](../README.md) and the living trees it links.

| Subdirectory | What it holds |
|---|---|
| [`planning/`](planning/) | The 2026-05 monorepo-consolidation era: dated design/plan pairs (foundation stand-up, Copybara sync, nexus-agent Swift, Dependabot, license checks) and the 2026-07 Pulumi migration notes |
| [`design/`](design/) | Completed platform designs (Cilium/Gateway API migration, Prometheus/Thanos HA) |
| [`foundation-port/`](foundation-port/) | The Terraform→Pulumi foundation port workstream: structural assessment, refactor plans, promotion-strategy decision record, cold-deploy race audit, and the `audit/` review trail |
| [`assessments/`](assessments/) | Whole-repo assessment (R5) and the CI-workflows audit — both explicitly superseded by `CONTRIBUTING.md` and the current workflow tree |
| [`gap-analysis/`](gap-analysis/) | The adversarially-verified Pulumi-vs-upstream gap analysis dataset (see the re-verification doc before trusting counts) |
| [`copybara/`](copybara/) | The one-way sync cutover narratives (superseded by the living [Copybara runbook](../admin/copybara-sync.md)) |

**Conventions:** artifacts are dated (`YYYY-MM-DD-…`) and carry a `Status:` line where
applicable. When a plan or spec in [`docs/superpowers/`](../superpowers/README.md)
completes, move it here.
