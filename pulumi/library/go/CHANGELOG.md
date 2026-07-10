# Changelog

## [2.1.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-foundation-v2.0.0...go-foundation-v2.1.0) (2026-07-10)


### Features

* **gcp-bootstrap:** trigger release ([550e1df](https://github.com/VitruvianSoftware/vitruvian-core/commit/550e1dffdb3525781923eb4f3369050dd77c5aec))
* **gcp-org:** trigger release ([3bb4b9e](https://github.com/VitruvianSoftware/vitruvian-core/commit/3bb4b9efab7fa9a8c59a9d68966d6f4c252fa89f))
* **org-folders:** trigger release ([588230c](https://github.com/VitruvianSoftware/vitruvian-core/commit/588230c68cc864fa77efd6324dc40c511e1ba0c7))


### Bug Fixes

* **foundation:** bootstrap polish before 1-org — deterministic bucket IAM + API-propagation wait ([#620](https://github.com/VitruvianSoftware/vitruvian-core/issues/620)) ([c41629f](https://github.com/VitruvianSoftware/vitruvian-core/commit/c41629fcbc38cc5dea1cf039b3885b0242de5a1e))
* **network:** declare v2 module path so v2 releases are consumable ([#784](https://github.com/VitruvianSoftware/vitruvian-core/issues/784)) ([d106303](https://github.com/VitruvianSoftware/vitruvian-core/commit/d1063037485d08a287882281e503347bcda847fc))
* **network:** enforce transitivity MIG-before-template teardown ordering ([#830](https://github.com/VitruvianSoftware/vitruvian-core/issues/830)) ([4f03633](https://github.com/VitruvianSoftware/vitruvian-core/commit/4f036335b366027c0b556eadc644258e0de2e80a))
* **network:** stop transitivity instance-template perpetual replace ([#782](https://github.com/VitruvianSoftware/vitruvian-core/issues/782)) ([513da0f](https://github.com/VitruvianSoftware/vitruvian-core/commit/513da0f72aad949010f0b76de2471af571e7444c))
* **pulumi-library/network:** avoid setting PrivateIpGoogleAccess on proxy subnets ([6062b15](https://github.com/VitruvianSoftware/vitruvian-core/commit/6062b15a42b23d7d9bc0cb3ce0fa77443cead52c))
* **pulumi-library/network:** sanitize PSC forwarding rule name for GCP compliance ([#751](https://github.com/VitruvianSoftware/vitruvian-core/issues/751)) ([2c4bb46](https://github.com/VitruvianSoftware/vitruvian-core/commit/2c4bb46b59571f1d69c30dbcebc31bea4aaa489c))
* **pulumi-library/network:** set CONNECTION balancing mode for INTERNAL backend service ([6c367e4](https://github.com/VitruvianSoftware/vitruvian-core/commit/6c367e4911fbe72f0dd302ccd245a26efea0bc7b))
* **pulumi-library:** decouple API enablement dependency ([#651](https://github.com/VitruvianSoftware/vitruvian-core/issues/651)) ([6a03698](https://github.com/VitruvianSoftware/vitruvian-core/commit/6a036986759a76888dbe279ce53f46ab3f8f5968))

## [2.0.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-foundation-v1.0.0...go-foundation-v2.0.0) (2026-07-06)


### ⚠ BREAKING CHANGES

* the eight Go modules above changed import paths; update imports to the new module paths.

### Features

* **go/networking:** support configuring VPC flow log options on SubnetArgs ([#61](https://github.com/VitruvianSoftware/vitruvian-core/issues/61)) ([b59626e](https://github.com/VitruvianSoftware/vitruvian-core/commit/b59626e41a03fc13ad98d5d74beeabe160dac64a))
* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* Phase 7 component parity ([#75](https://github.com/VitruvianSoftware/vitruvian-core/issues/75)) ([8e2647e](https://github.com/VitruvianSoftware/vitruvian-core/commit/8e2647e6d2b1f5312aea5d892339779dc8c97b4f))
* **pulumi/library:** integrate Go modules into the Bazel workspace ([b95e735](https://github.com/VitruvianSoftware/vitruvian-core/commit/b95e735574f373a9f08a31acb453ae6508ccc0b3))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))
* rename Go library packages to descriptive, upstream-consistent names ([2c31485](https://github.com/VitruvianSoftware/vitruvian-core/commit/2c314851ebd368cebf921437f7b615186ab9063d))


### Bug Fixes

* go mod tidy ([#72](https://github.com/VitruvianSoftware/vitruvian-core/issues/72)) ([134fc50](https://github.com/VitruvianSoftware/vitruvian-core/commit/134fc50751b20fa405c643c3844bce7258c234e2))
* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **go/vpc_sc:** allow ProjectNumbers to be dynamic ([#64](https://github.com/VitruvianSoftware/vitruvian-core/issues/64)) ([79cbecd](https://github.com/VitruvianSoftware/vitruvian-core/commit/79cbecd83c4954f55b4da7cf3a3d604f97d940a5))
* **logging:** grant bucketWriter instead of logWriter for log-bucket sinks ([#59](https://github.com/VitruvianSoftware/vitruvian-core/issues/59)) ([26800ab](https://github.com/VitruvianSoftware/vitruvian-core/commit/26800aba6753332306c01fba5c47a48036000311))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **pulumi/library:** satisfy conformance-check (canonical versions) ([6b73b37](https://github.com/VitruvianSoftware/vitruvian-core/commit/6b73b37b832ad1e6f5dd2ba1cfe0d2dc0aefd0bf))
* **tests:** fix library tests struct types ([#71](https://github.com/VitruvianSoftware/vitruvian-core/issues/71)) ([a51a2d8](https://github.com/VitruvianSoftware/vitruvian-core/commit/a51a2d8d805248ffef72d6c4529d17139ac33aeb))

## [1.0.0](https://github.com/VitruvianSoftware/pulumi-library/compare/go-foundation-v0.4.1...go-foundation-v1.0.0) (2026-07-04)

### ⚠ BREAKING CHANGES

- the eight Go modules above changed import paths; update imports to the new module paths.

### Features

- Phase 7 component parity ([#75](https://github.com/VitruvianSoftware/pulumi-library/issues/75)) ([45aae42](https://github.com/VitruvianSoftware/pulumi-library/commit/45aae42e9fb2a66f69654c486d1d01e2f7a67ffd))
- rename Go library packages to descriptive, upstream-consistent names ([6734481](https://github.com/VitruvianSoftware/pulumi-library/commit/6734481530f65d20d1a6de2f9dbb3bd5e6f7d43a))

### Bug Fixes

- **5-app-infra:** add missing compute_instance and instance_template properties ([#74](https://github.com/VitruvianSoftware/pulumi-library/issues/74)) ([53378ff](https://github.com/VitruvianSoftware/pulumi-library/commit/53378ff8764ddb63a5ffd9d4731b4aefd7e24911))

## [0.4.1](https://github.com/VitruvianSoftware/pulumi-library/compare/go-foundation-v0.4.0...go-foundation-v0.4.1) (2026-07-03)

### Bug Fixes

- go mod tidy ([#72](https://github.com/VitruvianSoftware/pulumi-library/issues/72)) ([633687e](https://github.com/VitruvianSoftware/pulumi-library/commit/633687e03eeb5042874d9da415648cdc13251165))
- **tests:** fix library tests struct types ([#71](https://github.com/VitruvianSoftware/pulumi-library/issues/71)) ([d6d73ed](https://github.com/VitruvianSoftware/pulumi-library/commit/d6d73edb3e703338a9d6f64adba003b6d9bdf293))

## [0.4.0](https://github.com/VitruvianSoftware/pulumi-library/compare/go-foundation-v0.3.1...go-foundation-v0.4.0) (2026-05-06)

### Features

- add 22 fine-grained library packages for foundation modular parity ([#48](https://github.com/VitruvianSoftware/pulumi-library/issues/48)) ([f54c6f2](https://github.com/VitruvianSoftware/pulumi-library/commit/f54c6f2a30ea4429a69e31ad3168aa3f075b0070))
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

## [0.2.0](https://github.com/VitruvianSoftware/pulumi-library/compare/v0.1.0...v0.2.0) (2026-04-22)

### Features

- restructure to polyglot monorepo with release-please ([#21](https://github.com/VitruvianSoftware/pulumi-library/issues/21)) ([942dbcf](https://github.com/VitruvianSoftware/pulumi-library/commit/942dbcf9f672d870489a679cf67ae819e1e5aee9))
