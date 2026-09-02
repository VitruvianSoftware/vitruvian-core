# E2E Test Infra: Enterprise Monorepo Scalability Overhaul

## Test Philosophy
- Opaque-box, requirement-driven verification derived strictly from `ORIGINAL_REQUEST.md`.
- Systematic multi-tier methodology: Category-Partition, Boundary Value Analysis (BVA), Pairwise Combinatorial Testing, Real-World Workload Testing, and Adversarial Coverage Hardening.

## Feature Inventory & Test Coverage
| # | Feature | Requirement | Tier 1 (Feature) | Tier 2 (Boundary) | Tier 3 (Pairwise) | Tier 4 (Workload) |
|---|---------|-------------|:----------------:|:-----------------:|:-----------------:|:-----------------:|
| 1 | Decoupled Pulumi State | R1 (Concurrency) | 5 | 5 | ✓ | ✓ |
| 2 | Bazel Boundary Aspect & Visibility | R1 (Isolation) | 5 | 5 | ✓ | ✓ |
| 3 | Hierarchical OWNERS Engine | R1 (Governance) | 5 | 5 | ✓ | ✓ |
| 4 | Speculative Merge Queue & Deploy Concurrency | R1 (Lanes) | 5 | 5 | ✓ | ✓ |
| 5 | Sub-Second Change Detection | R2 (Targeting) | 5 | 5 | ✓ | ✓ |
| 6 | Declarative Pipeline Units & DAG Generator | R2 (Pipelines) | 5 | 5 | ✓ | ✓ |
| 7 | Multi-Tier Presubmits & Gate Aggregator | R2 (Presubmit) | 5 | 5 | ✓ | ✓ |
| 8 | Persona / Operation Scoped Triggers | R2 (Triggers) | 5 | 5 | ✓ | ✓ |
| 9 | WIF Migration & Least-Privilege IAM | R3 (Identity) | 5 | 5 | ✓ | ✓ |
| 10 | Enterprise Secrets (ESO/ESC) | R3 (Secrets) | 5 | 5 | ✓ | ✓ |
| 11 | Automated Ephemeral Preview Environments | R3 (Previews) | 5 | 5 | ✓ | ✓ |
| 12 | Teardown Lifecycle & Ghost Reaper | R3 (Lifecycle) | 5 | 5 | ✓ | ✓ |

## Test Architecture
- Test Runner: Custom Bazel hermetic test targets in `//tests/e2e:...` and bash/python test suites executed via `bazel test`.
- Pass/Fail Semantics: Exit code 0 on passing all assertions; deterministic output assertions.
- Directory Layout:
  - `tests/e2e/r1_concurrency/` — Tests for state lock isolation, boundary aspects, OWNERS compiler, and deploy concurrency.
  - `tests/e2e/r2_pipelines/` — Tests for sub-second change detection, pipeline unit schema, dynamic DAG generator, and gate aggregator.
  - `tests/e2e/r3_identity_previews/` — Tests for WIF mappings, CEL IAM conditions, preview provisioning, and ghost reaper.
  - `tests/e2e/scenarios/` — Real-world application workloads (multi-team concurrent PRs, cross-app isolation, full lifecycle).

## Real-World Application Scenarios (Tier 4)
| # | Scenario | Features Exercised | Complexity |
|---|----------|--------------------|------------|
| 1 | High-Concurrency Multi-Team PR Presubmit | F5, F7, F8, F11 (Docs vs Frontend vs Backend vs Infra) | High |
| 2 | Concurrent IaC Stack Updates (No 409 Locks) | F1, F2, F4, F9 (Tabula + OAuth + Foundation parallel up) | High |
| 3 | Full Ephemeral Preview Lifecycle & Reaper | F11, F12, F15, F16 (PR open -> Preview -> Neon branch -> PR close -> Reaper) | High |
| 4 | Cross-Boundary Import Violation Gating | F2, F3, F4, F7 (Illegal import blocked by Bazel aspect & linter) | Medium |
| 5 | Sub-tree Code Ownership & Conformance Audit | F3, F5, F7 (OWNERS validation, CODEOWNERS compilation & coverage) | Medium |

## Coverage Thresholds
- Tier 1: $\ge 5$ test cases per feature ($12 \times 5 = 60$ test cases)
- Tier 2: $\ge 5$ boundary & corner test cases per feature ($12 \times 5 = 60$ test cases)
- Tier 3: $\ge 12$ pairwise cross-feature combination test cases
- Tier 4: $\ge 6$ real-world application workload scenarios
- Tier 5: Adversarial coverage hardening with Challenger analysis
- **Total Minimum Test Cases: $\ge 138$ test cases**
