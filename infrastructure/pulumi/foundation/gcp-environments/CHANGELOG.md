# Changelog

## [0.1.0](https://github.com/VitruvianSoftware/vitruvian-core/commits/foundation-gcp-environments-v0.1.0) (2026-07-08)

### Features

* **foundation:** promote 2-environments to live foundation with monorepo promotion workflow ([#TBD](https://github.com/VitruvianSoftware/vitruvian-core/pull/TBD))
  * Per-environment Pulumi stacks (development, nonproduction, production) with isolated state
  * Reusable workflow for chained promotion: dev (auto) → nonprod (manual) → prod (manual)
  * Creates fldr-{development,nonproduction,production} folders, prj-{d,n,p}-kms, prj-{d,n,p}-secrets
