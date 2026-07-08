# Changelog

## [0.2.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-environments-v0.1.0...foundation-gcp-environments-v0.2.0) (2026-07-08)


### Features

* **foundation:** promote 2-environments to live foundation with monorepo promotion workflow ([#724](https://github.com/VitruvianSoftware/vitruvian-core/issues/724)) ([fac7316](https://github.com/VitruvianSoftware/vitruvian-core/commit/fac7316710f19f1123a78488eaf56dd5ba0a7abf))
* **gcp-bootstrap:** trigger release ([550e1df](https://github.com/VitruvianSoftware/vitruvian-core/commit/550e1dffdb3525781923eb4f3369050dd77c5aec))
* **gcp-org:** trigger release ([3bb4b9e](https://github.com/VitruvianSoftware/vitruvian-core/commit/3bb4b9efab7fa9a8c59a9d68966d6f4c252fa89f))
* **org-folders:** trigger release ([588230c](https://github.com/VitruvianSoftware/vitruvian-core/commit/588230c68cc864fa77efd6324dc40c511e1ba0c7))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))

## [0.1.0](https://github.com/VitruvianSoftware/vitruvian-core/commits/foundation-gcp-environments-v0.1.0) (2026-07-08)

### Features

* **foundation:** promote 2-environments to live foundation with monorepo promotion workflow ([#TBD](https://github.com/VitruvianSoftware/vitruvian-core/pull/TBD))
  * Per-environment Pulumi stacks (development, nonproduction, production) with isolated state
  * Reusable workflow for chained promotion: dev (auto) → nonprod (manual) → prod (manual)
  * Creates fldr-{development,nonproduction,production} folders, prj-{d,n,p}-kms, prj-{d,n,p}-secrets
