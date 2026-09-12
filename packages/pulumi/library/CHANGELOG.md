# Changelog

All notable changes to the Vitruvian Software Pulumi Library will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `pkg/project` — Project factory with API enablement and default-VPC suppression
- `pkg/iam` — Multi-scope IAM bindings (additive + authoritative) for organization, folder, project, service account, and billing scopes
- `pkg/policy` — Organization policy enforcement (boolean + list constraints) using the v2 Org Policy API
- `pkg/networking` — VPC networks with subnets, secondary ranges, flow logs, and Private Service Access
- `pkg/app` — Cloud Run v2 service deployment with environment variables and ingress control
- `pkg/data` — BigQuery data platform with raw and curated datasets
- Comprehensive documentation for all packages (root README + per-package READMEs)
- `CONTRIBUTING.md` with design rules and package creation guidelines
- `SECURITY.md` with vulnerability reporting process
- `LICENSE` (Apache 2.0)
- GitHub Actions CI pipeline (`.github/workflows/ci.yml`)

### Fixed
- Eliminated `ApplyT` anti-pattern in IAM bindings — `ParentType` is now a plan-time `string`
- Eliminated `ApplyT` anti-pattern in Project API enablement — `ActivateApis` is now a plan-time `[]string`
