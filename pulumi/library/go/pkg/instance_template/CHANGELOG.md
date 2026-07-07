# Changelog

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-instance-template-v0.2.4...go-instance-template-v0.3.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate Go modules into the Bazel workspace ([b95e735](https://github.com/VitruvianSoftware/vitruvian-core/commit/b95e735574f373a9f08a31acb453ae6508ccc0b3))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **5-app-infra:** add missing compute_instance and instance_template properties ([#74](https://github.com/VitruvianSoftware/vitruvian-core/issues/74)) ([8fa4ce6](https://github.com/VitruvianSoftware/vitruvian-core/commit/8fa4ce6147737b7a1b2ae6a88f4849d86922f759))
* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **pulumi/library:** satisfy conformance-check (canonical versions) ([6b73b37](https://github.com/VitruvianSoftware/vitruvian-core/commit/6b73b37b832ad1e6f5dd2ba1cfe0d2dc0aefd0bf))
* **tests:** fix library tests struct types ([#71](https://github.com/VitruvianSoftware/vitruvian-core/issues/71)) ([a51a2d8](https://github.com/VitruvianSoftware/vitruvian-core/commit/a51a2d8d805248ffef72d6c4529d17139ac33aeb))
* update instance template Go structs for 5-app-infra gaps ([#70](https://github.com/VitruvianSoftware/vitruvian-core/issues/70)) ([34fef73](https://github.com/VitruvianSoftware/vitruvian-core/commit/34fef73736390e7816a177d31a098d516f725666))

## [0.2.3](https://github.com/VitruvianSoftware/pulumi-library/compare/go-instance-template-v0.2.2...go-instance-template-v0.2.3) (2026-07-04)

### Bug Fixes

- **5-app-infra:** add missing compute_instance and instance_template properties ([#74](https://github.com/VitruvianSoftware/pulumi-library/issues/74)) ([53378ff](https://github.com/VitruvianSoftware/pulumi-library/commit/53378ff8764ddb63a5ffd9d4731b4aefd7e24911))

## [0.2.2](https://github.com/VitruvianSoftware/pulumi-library/compare/go-instance-template-v0.2.1...go-instance-template-v0.2.2) (2026-07-03)

### Bug Fixes

- **tests:** fix library tests struct types ([#71](https://github.com/VitruvianSoftware/pulumi-library/issues/71)) ([d6d73ed](https://github.com/VitruvianSoftware/pulumi-library/commit/d6d73edb3e703338a9d6f64adba003b6d9bdf293))
- update instance template Go structs for 5-app-infra gaps ([#70](https://github.com/VitruvianSoftware/pulumi-library/issues/70)) ([41cd6bc](https://github.com/VitruvianSoftware/pulumi-library/commit/41cd6bc7af83d7a8b4b90cb63aa8d0f39cc0a774))

## [0.2.1](https://github.com/VitruvianSoftware/pulumi-library/compare/go-instance-template-v0.2.0...go-instance-template-v0.2.1) (2026-05-07)

### Bug Fixes

- achieve 100% architectural parity ([#55](https://github.com/VitruvianSoftware/pulumi-library/issues/55)) ([26036da](https://github.com/VitruvianSoftware/pulumi-library/commit/26036da5f46c1d49cfe9fbace41ea23ed6f51e11))

## [0.2.0](https://github.com/VitruvianSoftware/pulumi-library/compare/go-instance-template-v0.1.0...go-instance-template-v0.2.0) (2026-05-06)

### Features

- add 22 fine-grained library packages for foundation modular parity ([#48](https://github.com/VitruvianSoftware/pulumi-library/issues/48)) ([f54c6f2](https://github.com/VitruvianSoftware/pulumi-library/commit/f54c6f2a30ea4429a69e31ad3168aa3f075b0070))

### Bug Fixes

- **ts:** trigger release ([1bcb6fa](https://github.com/VitruvianSoftware/pulumi-library/commit/1bcb6faa91d8c2bb7d6b80c6ec1e081bf8e136b6))
