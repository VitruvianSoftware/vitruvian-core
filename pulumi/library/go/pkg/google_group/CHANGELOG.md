# Changelog

## [1.0.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/v1.0.2...v1.0.1) (2026-07-06)


### ⚠ BREAKING CHANGES

* the eight Go modules above changed import paths; update imports to the new module paths.

### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate Go modules into the Bazel workspace ([b95e735](https://github.com/VitruvianSoftware/vitruvian-core/commit/b95e735574f373a9f08a31acb453ae6508ccc0b3))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))
* rename Go library packages to descriptive, upstream-consistent names ([2c31485](https://github.com/VitruvianSoftware/vitruvian-core/commit/2c314851ebd368cebf921437f7b615186ab9063d))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **go:** publish go-module path-format tags for renamed packages ([c67121c](https://github.com/VitruvianSoftware/vitruvian-core/commit/c67121cadadfa758450cd21c86c9df005ba21a77))
* **go:** publish go-module path-format tags for renamed packages ([50a09da](https://github.com/VitruvianSoftware/vitruvian-core/commit/50a09da07afd6a27be5ffbd9288ac285171f25e2))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **pulumi/library:** satisfy conformance-check (canonical versions) ([6b73b37](https://github.com/VitruvianSoftware/vitruvian-core/commit/6b73b37b832ad1e6f5dd2ba1cfe0d2dc0aefd0bf))

## [1.0.1](https://github.com/VitruvianSoftware/pulumi-library/compare/v1.0.0...v1.0.1) (2026-07-04)

### ⚠ BREAKING CHANGES

- the eight Go modules above changed import paths; update imports to the new module paths.

### Features

- rename Go library packages to descriptive, upstream-consistent names ([6734481](https://github.com/VitruvianSoftware/pulumi-library/commit/6734481530f65d20d1a6de2f9dbb3bd5e6f7d43a))

### Bug Fixes

- **go:** publish go-module path-format tags for renamed packages ([7b56cb0](https://github.com/VitruvianSoftware/pulumi-library/commit/7b56cb050503d53da230899e79f58721945c3ec3))
- **go:** publish go-module path-format tags for renamed packages ([cbbb8b1](https://github.com/VitruvianSoftware/pulumi-library/commit/cbbb8b185bdd2b6b3b848731ddb535cefd3c6a8d))
- **ts:** trigger release ([1bcb6fa](https://github.com/VitruvianSoftware/pulumi-library/commit/1bcb6faa91d8c2bb7d6b80c6ec1e081bf8e136b6))

## [1.0.0](https://github.com/VitruvianSoftware/pulumi-library/compare/go-google-group-v0.4.1...go-google-group-v1.0.0) (2026-07-04)

### ⚠ BREAKING CHANGES

- the eight Go modules above changed import paths; update imports to the new module paths.

### Features

- rename Go library packages to descriptive, upstream-consistent names ([6734481](https://github.com/VitruvianSoftware/pulumi-library/commit/6734481530f65d20d1a6de2f9dbb3bd5e6f7d43a))

### Bug Fixes

- **ts:** trigger release ([1bcb6fa](https://github.com/VitruvianSoftware/pulumi-library/commit/1bcb6faa91d8c2bb7d6b80c6ec1e081bf8e136b6))

## [0.4.1](https://github.com/VitruvianSoftware/pulumi-library/compare/go-group-v0.4.0...go-group-v0.4.1) (2026-07-03)

### Bug Fixes

- **tests:** fix library tests struct types ([#71](https://github.com/VitruvianSoftware/pulumi-library/issues/71)) ([d6d73ed](https://github.com/VitruvianSoftware/pulumi-library/commit/d6d73edb3e703338a9d6f64adba003b6d9bdf293))

## [0.4.0](https://github.com/VitruvianSoftware/pulumi-library/compare/go-group-v0.3.1...go-group-v0.4.0) (2026-05-06)

### Features

- **library:** refactor to independent workspaces for go and ts ([df88451](https://github.com/VitruvianSoftware/pulumi-library/commit/df88451e4195f05d5b8455085d2806c4e96ee6a3))
- restructure to polyglot monorepo with release-please ([#21](https://github.com/VitruvianSoftware/pulumi-library/issues/21)) ([942dbcf](https://github.com/VitruvianSoftware/pulumi-library/commit/942dbcf9f672d870489a679cf67ae819e1e5aee9))

### Bug Fixes

- **library:** resolve workspace dependencies and test config ([b48fd3f](https://github.com/VitruvianSoftware/pulumi-library/commit/b48fd3f9aec3df5c2193c8997d7bbc7fd43d1719))
- **library:** resolve workspace dependencies and test config ([781c2d1](https://github.com/VitruvianSoftware/pulumi-library/commit/781c2d1d2bb7a51c21cd6917bd8d51bea2ea49b4))
- **ts:** trigger release ([1bcb6fa](https://github.com/VitruvianSoftware/pulumi-library/commit/1bcb6faa91d8c2bb7d6b80c6ec1e081bf8e136b6))

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
