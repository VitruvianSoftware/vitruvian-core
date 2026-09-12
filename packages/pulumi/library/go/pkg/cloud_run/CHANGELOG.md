# Changelog

## [1.0.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-cloud-run-v1.0.0...go-cloud-run-v1.0.1) (2026-07-27)


### Bug Fixes

* **deps:** bump klauspost/compress to v1.18.7 (GO-2026-5841) — unwedges the merge queue ([#1268](https://github.com/VitruvianSoftware/vitruvian-core/issues/1268)) ([338f365](https://github.com/VitruvianSoftware/vitruvian-core/commit/338f365b0f84b328c0bf880ca0ebb4595590b8bd))

## [1.0.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-cloud-run-v0.3.0...go-cloud-run-v1.0.0) (2026-07-23)


### ⚠ BREAKING CHANGES

* **cloud_run:** Region is a pulumi.StringInput ([#1090](https://github.com/VitruvianSoftware/vitruvian-core/issues/1090))

### Features

* **cloud_run:** Region is a pulumi.StringInput ([#1090](https://github.com/VitruvianSoftware/vitruvian-core/issues/1090)) ([3703539](https://github.com/VitruvianSoftware/vitruvian-core/commit/3703539755e20b2af3527d0b41f38d6706fd17ac))

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-cloud-run-v0.2.0...go-cloud-run-v0.3.0) (2026-07-18)


### Features

* **cloud_run:** v0.3.0 blue-green (revision naming + traffic split) + serverless_space passthrough ([#892](https://github.com/VitruvianSoftware/vitruvian-core/issues/892)) ([56268ac](https://github.com/VitruvianSoftware/vitruvian-core/commit/56268ace09d0150dc9abc2dbe4875517237acce0))

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
