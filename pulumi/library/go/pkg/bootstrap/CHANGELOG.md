# Changelog

## [2.1.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-bootstrap-v2.0.0...go-bootstrap-v2.1.0) (2026-07-08)


### Features

* **gcp-bootstrap:** trigger release ([550e1df](https://github.com/VitruvianSoftware/vitruvian-core/commit/550e1dffdb3525781923eb4f3369050dd77c5aec))
* **gcp-org:** trigger release ([3bb4b9e](https://github.com/VitruvianSoftware/vitruvian-core/commit/3bb4b9efab7fa9a8c59a9d68966d6f4c252fa89f))
* **org-folders:** trigger release ([588230c](https://github.com/VitruvianSoftware/vitruvian-core/commit/588230c68cc864fa77efd6324dc40c511e1ba0c7))


### Bug Fixes

* **pulumi-library:** decouple API enablement dependency ([#651](https://github.com/VitruvianSoftware/vitruvian-core/issues/651)) ([6a03698](https://github.com/VitruvianSoftware/vitruvian-core/commit/6a036986759a76888dbe279ce53f46ab3f8f5968))

## [2.0.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-bootstrap-v1.0.1...go-bootstrap-v2.0.0) (2026-07-06)


### ⚠ BREAKING CHANGES

* the eight Go modules above changed import paths; update imports to the new module paths.

### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate Go modules into the Bazel workspace ([b95e735](https://github.com/VitruvianSoftware/vitruvian-core/commit/b95e735574f373a9f08a31acb453ae6508ccc0b3))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))
* rename Go library packages to descriptive, upstream-consistent names ([2c31485](https://github.com/VitruvianSoftware/vitruvian-core/commit/2c314851ebd368cebf921437f7b615186ab9063d))


### Bug Fixes

* **bootstrap:** always enable impersonation APIs on the seed project ([6502dd4](https://github.com/VitruvianSoftware/vitruvian-core/commit/6502dd4823d4f1cb76899c2bcce16ee681574725))
* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **pulumi/library:** satisfy conformance-check (canonical versions) ([6b73b37](https://github.com/VitruvianSoftware/vitruvian-core/commit/6b73b37b832ad1e6f5dd2ba1cfe0d2dc0aefd0bf))
* **tests:** fix library tests struct types ([#71](https://github.com/VitruvianSoftware/vitruvian-core/issues/71)) ([a51a2d8](https://github.com/VitruvianSoftware/vitruvian-core/commit/a51a2d8d805248ffef72d6c4529d17139ac33aeb))
* **ts/centralized-logging:** stop clobbering linkedDatasetName ([f0926e8](https://github.com/VitruvianSoftware/vitruvian-core/commit/f0926e87f57ba78daaebfd51f680607b444aca73))

## [1.0.0](https://github.com/VitruvianSoftware/pulumi-library/compare/go-bootstrap-v0.4.1...go-bootstrap-v1.0.0) (2026-07-04)

### ⚠ BREAKING CHANGES

- the eight Go modules above changed import paths; update imports to the new module paths.

### Features

- rename Go library packages to descriptive, upstream-consistent names ([6734481](https://github.com/VitruvianSoftware/pulumi-library/commit/6734481530f65d20d1a6de2f9dbb3bd5e6f7d43a))

### Bug Fixes

- **bootstrap:** always enable impersonation APIs on the seed project ([8063653](https://github.com/VitruvianSoftware/pulumi-library/commit/806365320fa047980cd307c163aa92d1a7be81a9))
- **ts/centralized-logging:** stop clobbering linkedDatasetName ([b0189b2](https://github.com/VitruvianSoftware/pulumi-library/commit/b0189b2d6c3b5c7b70dd2e6294b237778ef8cb10))

## [0.4.1](https://github.com/VitruvianSoftware/pulumi-library/compare/go-bootstrap-v0.4.0...go-bootstrap-v0.4.1) (2026-07-03)

### Bug Fixes

- **tests:** fix library tests struct types ([#71](https://github.com/VitruvianSoftware/pulumi-library/issues/71)) ([d6d73ed](https://github.com/VitruvianSoftware/pulumi-library/commit/d6d73edb3e703338a9d6f64adba003b6d9bdf293))

## [0.4.0](https://github.com/VitruvianSoftware/pulumi-library/compare/go-bootstrap-v0.3.2...go-bootstrap-v0.4.0) (2026-05-06)

### Features

- **library:** refactor to independent workspaces for go and ts ([df88451](https://github.com/VitruvianSoftware/pulumi-library/commit/df88451e4195f05d5b8455085d2806c4e96ee6a3))
- restructure to polyglot monorepo with release-please ([#21](https://github.com/VitruvianSoftware/pulumi-library/issues/21)) ([942dbcf](https://github.com/VitruvianSoftware/pulumi-library/commit/942dbcf9f672d870489a679cf67ae819e1e5aee9))

### Bug Fixes

- add kms and gcs region parity to bootstrap component ([#41](https://github.com/VitruvianSoftware/pulumi-library/issues/41)) ([5d6cb35](https://github.com/VitruvianSoftware/pulumi-library/commit/5d6cb359b7d6970792b5e741a82f4cdc4032cef9))
- grant kms encrypterDecrypter to gcs service agent before bucket creation ([5543345](https://github.com/VitruvianSoftware/pulumi-library/commit/55433459ca6389cfbf4e06661bf49ce595b898f5))
- **library:** resolve workspace dependencies and test config ([b48fd3f](https://github.com/VitruvianSoftware/pulumi-library/commit/b48fd3f9aec3df5c2193c8997d7bbc7fd43d1719))
- **library:** resolve workspace dependencies and test config ([781c2d1](https://github.com/VitruvianSoftware/pulumi-library/commit/781c2d1d2bb7a51c21cd6917bd8d51bea2ea49b4))
- **ts:** trigger release ([1bcb6fa](https://github.com/VitruvianSoftware/pulumi-library/commit/1bcb6faa91d8c2bb7d6b80c6ec1e081bf8e136b6))

## [0.3.2](https://github.com/VitruvianSoftware/pulumi-library/compare/v0.3.1...v0.3.2) (2026-04-23)

### Bug Fixes

- add kms and gcs region parity to bootstrap component ([#41](https://github.com/VitruvianSoftware/pulumi-library/issues/41)) ([5d6cb35](https://github.com/VitruvianSoftware/pulumi-library/commit/5d6cb359b7d6970792b5e741a82f4cdc4032cef9))
- grant kms encrypterDecrypter to gcs service agent before bucket creation ([5543345](https://github.com/VitruvianSoftware/pulumi-library/commit/55433459ca6389cfbf4e06661bf49ce595b898f5))

## [0.3.1](https://github.com/VitruvianSoftware/pulumi-library/compare/v0.3.0...v0.3.1) (2026-04-23)

### Bug Fixes

- **ts:** trigger release ([1bcb6fa](https://github.com/VitruvianSoftware/pulumi-library/commit/1bcb6faa91d8c2bb7d6b80c6ec1e081bf8e136b6))

## [0.3.0](https://github.com/VitruvianSoftware/pulumi-library/compare/v0.2.0...v0.3.0) (2026-04-23)

### Features

- **library:** refactor to independent workspaces for go and ts ([df88451](https://github.com/VitruvianSoftware/pulumi-library/commit/df88451e4195f05d5b8455085d2806c4e96ee6a3))

### Bug Fixes

- **library:** resolve workspace dependencies and test config ([b48fd3f](https://github.com/VitruvianSoftware/pulumi-library/commit/b48fd3f9aec3df5c2193c8997d7bbc7fd43d1719))
- **library:** resolve workspace dependencies and test config ([781c2d1](https://github.com/VitruvianSoftware/pulumi-library/commit/781c2d1d2bb7a51c21cd6917bd8d51bea2ea49b4))

## [0.2.0](https://github.com/VitruvianSoftware/pulumi-library/compare/v0.1.0...v0.2.0) (2026-04-23)

### Features

- **library:** refactor to independent workspaces for go and ts ([df88451](https://github.com/VitruvianSoftware/pulumi-library/commit/df88451e4195f05d5b8455085d2806c4e96ee6a3))
- restructure to polyglot monorepo with release-please ([#21](https://github.com/VitruvianSoftware/pulumi-library/issues/21)) ([942dbcf](https://github.com/VitruvianSoftware/pulumi-library/commit/942dbcf9f672d870489a679cf67ae819e1e5aee9))

### Bug Fixes

- **library:** resolve workspace dependencies and test config ([b48fd3f](https://github.com/VitruvianSoftware/pulumi-library/commit/b48fd3f9aec3df5c2193c8997d7bbc7fd43d1719))
- **library:** resolve workspace dependencies and test config ([781c2d1](https://github.com/VitruvianSoftware/pulumi-library/commit/781c2d1d2bb7a51c21cd6917bd8d51bea2ea49b4))
