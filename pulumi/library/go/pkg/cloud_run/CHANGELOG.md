# Changelog

## [0.2.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-cloud-run-v0.1.0...go-cloud-run-v0.2.0) (2026-07-11)


### Features

* **gcp-bootstrap:** trigger release ([550e1df](https://github.com/VitruvianSoftware/vitruvian-core/commit/550e1dffdb3525781923eb4f3369050dd77c5aec))
* **gcp-org:** trigger release ([3bb4b9e](https://github.com/VitruvianSoftware/vitruvian-core/commit/3bb4b9efab7fa9a8c59a9d68966d6f4c252fa89f))
* **org-folders:** trigger release ([588230c](https://github.com/VitruvianSoftware/vitruvian-core/commit/588230c68cc864fa77efd6324dc40c511e1ba0c7))
* **oss-stage:** pkg/cloud_run primitive + serverless_space module (Phase 2) ([#873](https://github.com/VitruvianSoftware/vitruvian-core/issues/873)) ([b3f2331](https://github.com/VitruvianSoftware/vitruvian-core/commit/b3f23318f41fd00053507135388f53cd87229bd8))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))

## 0.1.0

- Initial release: Cloud Run v2 service component with autoscaling defaults,
  resource limits, ingress control, plain + Secret Manager-backed env vars.

## 0.3.0

- Add blue-green support: `RevisionName` (named revisions) and `Traffics`
  (per-revision traffic split with optional tags) for candidate→promote deploys.
