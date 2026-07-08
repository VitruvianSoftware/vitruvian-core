# Changelog

## [0.5.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-kms-v0.4.0...foundation-kms-v0.5.0) (2026-07-08)


### Features

* **gcp-bootstrap:** trigger release ([550e1df](https://github.com/VitruvianSoftware/vitruvian-core/commit/550e1dffdb3525781923eb4f3369050dd77c5aec))
* **gcp-org:** trigger release ([3bb4b9e](https://github.com/VitruvianSoftware/vitruvian-core/commit/3bb4b9efab7fa9a8c59a9d68966d6f4c252fa89f))
* **org-folders:** trigger release ([588230c](https://github.com/VitruvianSoftware/vitruvian-core/commit/588230c68cc864fa77efd6324dc40c511e1ba0c7))


### Bug Fixes

* **pulumi-library:** decouple API enablement dependency ([#651](https://github.com/VitruvianSoftware/vitruvian-core/issues/651)) ([6a03698](https://github.com/VitruvianSoftware/vitruvian-core/commit/6a036986759a76888dbe279ce53f46ab3f8f5968))

## [0.4.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-kms-v0.3.0...foundation-kms-v0.4.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))

## [0.3.0](https://github.com/VitruvianSoftware/pulumi-library/compare/foundation-kms-v0.2.4...foundation-kms-v0.3.0) (2026-04-23)

### Features

- **library:** refactor to independent workspaces for go and ts ([df88451](https://github.com/VitruvianSoftware/pulumi-library/commit/df88451e4195f05d5b8455085d2806c4e96ee6a3))

### Bug Fixes

- **ci:** configure npm publishing to github packages ([#35](https://github.com/VitruvianSoftware/pulumi-library/issues/35)) ([3c847ac](https://github.com/VitruvianSoftware/pulumi-library/commit/3c847acd3c768edfefb9a0da2b5112109a2d5a1f))
- **library:** resolve workspace dependencies and test config ([b48fd3f](https://github.com/VitruvianSoftware/pulumi-library/commit/b48fd3f9aec3df5c2193c8997d7bbc7fd43d1719))
- **library:** resolve workspace dependencies and test config ([781c2d1](https://github.com/VitruvianSoftware/pulumi-library/commit/781c2d1d2bb7a51c21cd6917bd8d51bea2ea49b4))
- **ts:** add repository field to package.json ([4a21652](https://github.com/VitruvianSoftware/pulumi-library/commit/4a216520d0c7480834407db63574b39f339de4ca))
- **ts:** make npm packages public ([1c47b53](https://github.com/VitruvianSoftware/pulumi-library/commit/1c47b530a70156a4a4f7d25211050f6991bd2ee1))
- **ts:** trigger release ([1bcb6fa](https://github.com/VitruvianSoftware/pulumi-library/commit/1bcb6faa91d8c2bb7d6b80c6ec1e081bf8e136b6))

## [0.2.4](https://github.com/VitruvianSoftware/pulumi-library/compare/pulumi-kms-v0.2.3...pulumi-kms-v0.2.4) (2026-04-23)

### Bug Fixes

- **ts:** trigger release ([1bcb6fa](https://github.com/VitruvianSoftware/pulumi-library/commit/1bcb6faa91d8c2bb7d6b80c6ec1e081bf8e136b6))

## [0.2.3](https://github.com/VitruvianSoftware/pulumi-library/compare/pulumi-kms-v0.2.2...pulumi-kms-v0.2.3) (2026-04-23)

### Bug Fixes

- **ts:** make npm packages public ([1c47b53](https://github.com/VitruvianSoftware/pulumi-library/commit/1c47b530a70156a4a4f7d25211050f6991bd2ee1))

## [0.2.2](https://github.com/VitruvianSoftware/pulumi-library/compare/pulumi-kms-v0.2.1...pulumi-kms-v0.2.2) (2026-04-23)

### Bug Fixes

- **ts:** add repository field to package.json ([4a21652](https://github.com/VitruvianSoftware/pulumi-library/commit/4a216520d0c7480834407db63574b39f339de4ca))

## [0.2.1](https://github.com/VitruvianSoftware/pulumi-library/compare/pulumi-kms-v0.2.0...pulumi-kms-v0.2.1) (2026-04-23)

### Bug Fixes

- **ci:** configure npm publishing to github packages ([#35](https://github.com/VitruvianSoftware/pulumi-library/issues/35)) ([3c847ac](https://github.com/VitruvianSoftware/pulumi-library/commit/3c847acd3c768edfefb9a0da2b5112109a2d5a1f))

## [0.2.0](https://github.com/VitruvianSoftware/pulumi-library/compare/pulumi-kms-v0.1.0...pulumi-kms-v0.2.0) (2026-04-23)

### Features

- **library:** refactor to independent workspaces for go and ts ([df88451](https://github.com/VitruvianSoftware/pulumi-library/commit/df88451e4195f05d5b8455085d2806c4e96ee6a3))

### Bug Fixes

- **library:** resolve workspace dependencies and test config ([b48fd3f](https://github.com/VitruvianSoftware/pulumi-library/commit/b48fd3f9aec3df5c2193c8997d7bbc7fd43d1719))
- **library:** resolve workspace dependencies and test config ([781c2d1](https://github.com/VitruvianSoftware/pulumi-library/commit/781c2d1d2bb7a51c21cd6917bd8d51bea2ea49b4))
