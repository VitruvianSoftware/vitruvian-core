# Changelog

## [2.0.2](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-network-v2.0.1...go-network-v2.0.2) (2026-07-10)


### Bug Fixes

* **network:** declare v2 module path so v2 releases are consumable ([#784](https://github.com/VitruvianSoftware/vitruvian-core/issues/784)) ([d106303](https://github.com/VitruvianSoftware/vitruvian-core/commit/d1063037485d08a287882281e503347bcda847fc))

## [2.0.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-network-v2.0.0...go-network-v2.0.1) (2026-07-10)


### Bug Fixes

* **network:** stop transitivity instance-template perpetual replace ([#782](https://github.com/VitruvianSoftware/vitruvian-core/issues/782)) ([513da0f](https://github.com/VitruvianSoftware/vitruvian-core/commit/513da0f72aad949010f0b76de2471af571e7444c))
* **pulumi-library/network:** avoid setting PrivateIpGoogleAccess on proxy subnets ([6062b15](https://github.com/VitruvianSoftware/vitruvian-core/commit/6062b15a42b23d7d9bc0cb3ce0fa77443cead52c))
* **pulumi-library/network:** set CONNECTION balancing mode for INTERNAL backend service ([6c367e4](https://github.com/VitruvianSoftware/vitruvian-core/commit/6c367e4911fbe72f0dd302ccd245a26efea0bc7b))

## [2.0.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-network-v1.0.1...go-network-v2.0.0) (2026-07-08)


### ⚠ BREAKING CHANGES

* the eight Go modules above changed import paths; update imports to the new module paths.

### Features

* **gcp-bootstrap:** trigger release ([550e1df](https://github.com/VitruvianSoftware/vitruvian-core/commit/550e1dffdb3525781923eb4f3369050dd77c5aec))
* **gcp-org:** trigger release ([3bb4b9e](https://github.com/VitruvianSoftware/vitruvian-core/commit/3bb4b9efab7fa9a8c59a9d68966d6f4c252fa89f))
* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **org-folders:** trigger release ([588230c](https://github.com/VitruvianSoftware/vitruvian-core/commit/588230c68cc864fa77efd6324dc40c511e1ba0c7))
* **pulumi/library:** integrate Go modules into the Bazel workspace ([b95e735](https://github.com/VitruvianSoftware/vitruvian-core/commit/b95e735574f373a9f08a31acb453ae6508ccc0b3))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))
* **pulumi/library:** multi-package publish-on-version-bump + corrected export transforms ([#598](https://github.com/VitruvianSoftware/vitruvian-core/issues/598)) ([ba92a6b](https://github.com/VitruvianSoftware/vitruvian-core/commit/ba92a6b0d709e21bae78e1f3ef844cc1c5f4e16b))
* rename Go library packages to descriptive, upstream-consistent names ([2c31485](https://github.com/VitruvianSoftware/vitruvian-core/commit/2c314851ebd368cebf921437f7b615186ab9063d))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **go:** publish go-module path-format tags for renamed packages ([c67121c](https://github.com/VitruvianSoftware/vitruvian-core/commit/c67121cadadfa758450cd21c86c9df005ba21a77))
* **go:** publish go-module path-format tags for renamed packages ([50a09da](https://github.com/VitruvianSoftware/vitruvian-core/commit/50a09da07afd6a27be5ffbd9288ac285171f25e2))
* **pulumi-library/network:** sanitize PSC forwarding rule name for GCP compliance ([#751](https://github.com/VitruvianSoftware/vitruvian-core/issues/751)) ([2c4bb46](https://github.com/VitruvianSoftware/vitruvian-core/commit/2c4bb46b59571f1d69c30dbcebc31bea4aaa489c))
* **pulumi-library:** decouple API enablement dependency ([#651](https://github.com/VitruvianSoftware/vitruvian-core/issues/651)) ([6a03698](https://github.com/VitruvianSoftware/vitruvian-core/commit/6a036986759a76888dbe279ce53f46ab3f8f5968))
* **pulumi/library:** forward-port published features the graft missed + reconcile manifest ([#597](https://github.com/VitruvianSoftware/vitruvian-core/issues/597)) ([7f43cec](https://github.com/VitruvianSoftware/vitruvian-core/commit/7f43cecd822d7b7abf480f037389a55c64d0b25c))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **pulumi/library:** satisfy conformance-check (canonical versions) ([6b73b37](https://github.com/VitruvianSoftware/vitruvian-core/commit/6b73b37b832ad1e6f5dd2ba1cfe0d2dc0aefd0bf))

## [1.0.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/v1.1.0...v1.0.1) (2026-07-06)


### ⚠ BREAKING CHANGES

* the eight Go modules above changed import paths; update imports to the new module paths.

### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate Go modules into the Bazel workspace ([b95e735](https://github.com/VitruvianSoftware/vitruvian-core/commit/b95e735574f373a9f08a31acb453ae6508ccc0b3))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))
* **pulumi/library:** multi-package publish-on-version-bump + corrected export transforms ([#598](https://github.com/VitruvianSoftware/vitruvian-core/issues/598)) ([ba92a6b](https://github.com/VitruvianSoftware/vitruvian-core/commit/ba92a6b0d709e21bae78e1f3ef844cc1c5f4e16b))
* rename Go library packages to descriptive, upstream-consistent names ([2c31485](https://github.com/VitruvianSoftware/vitruvian-core/commit/2c314851ebd368cebf921437f7b615186ab9063d))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **go:** publish go-module path-format tags for renamed packages ([c67121c](https://github.com/VitruvianSoftware/vitruvian-core/commit/c67121cadadfa758450cd21c86c9df005ba21a77))
* **go:** publish go-module path-format tags for renamed packages ([50a09da](https://github.com/VitruvianSoftware/vitruvian-core/commit/50a09da07afd6a27be5ffbd9288ac285171f25e2))
* **pulumi/library:** forward-port published features the graft missed + reconcile manifest ([#597](https://github.com/VitruvianSoftware/vitruvian-core/issues/597)) ([7f43cec](https://github.com/VitruvianSoftware/vitruvian-core/commit/7f43cecd822d7b7abf480f037389a55c64d0b25c))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
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

## [1.0.0](https://github.com/VitruvianSoftware/pulumi-library/compare/go-network-v0.5.1...go-network-v1.0.0) (2026-07-04)

### ⚠ BREAKING CHANGES

- the eight Go modules above changed import paths; update imports to the new module paths.

### Features

- rename Go library packages to descriptive, upstream-consistent names ([6734481](https://github.com/VitruvianSoftware/pulumi-library/commit/6734481530f65d20d1a6de2f9dbb3bd5e6f7d43a))

### Bug Fixes

- **ts:** trigger release ([1bcb6fa](https://github.com/VitruvianSoftware/pulumi-library/commit/1bcb6faa91d8c2bb7d6b80c6ec1e081bf8e136b6))

## [0.5.1](https://github.com/VitruvianSoftware/pulumi-library/compare/go-networking-v0.5.0...go-networking-v0.5.1) (2026-07-03)

### Bug Fixes

- **tests:** fix library tests struct types ([#71](https://github.com/VitruvianSoftware/pulumi-library/issues/71)) ([d6d73ed](https://github.com/VitruvianSoftware/pulumi-library/commit/d6d73edb3e703338a9d6f64adba003b6d9bdf293))

## [0.5.0](https://github.com/VitruvianSoftware/pulumi-library/compare/go-networking-v0.4.0...go-networking-v0.5.0) (2026-07-03)

### Features

- **go/networking:** support configuring VPC flow log options on SubnetArgs ([#61](https://github.com/VitruvianSoftware/pulumi-library/issues/61)) ([a71371f](https://github.com/VitruvianSoftware/pulumi-library/commit/a71371f11968c5cfb9ebf3ffe48e5cbdf249f160))

## [0.4.0](https://github.com/VitruvianSoftware/pulumi-library/compare/go-networking-v0.3.1...go-networking-v0.4.0) (2026-05-06)

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
