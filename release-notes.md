:robot: I have created a release *beep* *boop*
---


<details><summary>foundation-library: 0.9.0</summary>

## [0.9.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-library-v0.8.0...foundation-library-v0.9.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* Phase 7 component parity ([#75](https://github.com/VitruvianSoftware/vitruvian-core/issues/75)) ([8e2647e](https://github.com/VitruvianSoftware/vitruvian-core/commit/8e2647e6d2b1f5312aea5d892339779dc8c97b4f))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** correct TS BUILD load path; revert devx/homelab go.mod ([5f125db](https://github.com/VitruvianSoftware/vitruvian-core/commit/5f125db6885a95a38886c8d2b0d618de1e7c5e9b))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **pulumi/library:** satisfy conformance-check (canonical versions) ([6b73b37](https://github.com/VitruvianSoftware/vitruvian-core/commit/6b73b37b832ad1e6f5dd2ba1cfe0d2dc0aefd0bf))
* **ts:** allow Input&lt;string&gt; for CentralizedLogging bucketName ([#68](https://github.com/VitruvianSoftware/vitruvian-core/issues/68)) ([7b42f10](https://github.com/VitruvianSoftware/vitruvian-core/commit/7b42f10126ff1864ce228185c5f0201b6c456cb8))
</details>

<details><summary>go-foundation: 2.0.0</summary>

## [2.0.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-foundation-v1.0.0...go-foundation-v2.0.0) (2026-07-06)


###   BREAKING CHANGES

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
</details>

<details><summary>foundation-budget: 0.4.0</summary>

## [0.4.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-budget-v0.3.0...foundation-budget-v0.4.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
</details>

<details><summary>foundation-cb-private-pool: 0.4.0</summary>

## [0.4.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-cb-private-pool-v0.3.1...foundation-cb-private-pool-v0.4.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
</details>

<details><summary>foundation-centralized-logging: 0.7.0</summary>

## [0.7.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-centralized-logging-v0.6.0...foundation-centralized-logging-v0.7.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **ts/centralized-logging:** add Log Analytics, linked dataset, folder sinks ([#66](https://github.com/VitruvianSoftware/vitruvian-core/issues/66)) ([8404e61](https://github.com/VitruvianSoftware/vitruvian-core/commit/8404e61ce508b983cd1e02dd81c38df337c36932))
* **ts/centralized-logging:** stop clobbering linkedDatasetName ([f0926e8](https://github.com/VitruvianSoftware/vitruvian-core/commit/f0926e87f57ba78daaebfd51f680607b444aca73))
* **ts/centralized-logging:** stop clobbering linkedDatasetName ([1c299a6](https://github.com/VitruvianSoftware/vitruvian-core/commit/1c299a6e30cb5d578b7658def24b01999341fba5))
* **ts/psc:** add support for target, noAutomateDnsZone, and serviceDirectoryRegistrations ([#65](https://github.com/VitruvianSoftware/vitruvian-core/issues/65)) ([8a3d9b1](https://github.com/VitruvianSoftware/vitruvian-core/commit/8a3d9b170214d2296cfbb9d8764841fffc6d954a))
* **ts:** allow Input&lt;string&gt; for CentralizedLogging bucketName ([#68](https://github.com/VitruvianSoftware/vitruvian-core/issues/68)) ([7b42f10](https://github.com/VitruvianSoftware/vitruvian-core/commit/7b42f10126ff1864ce228185c5f0201b6c456cb8))
</details>

<details><summary>foundation-dns-hub: 0.4.0</summary>

## [0.4.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-dns-hub-v0.3.0...foundation-dns-hub-v0.4.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
</details>

<details><summary>foundation-google-group: 0.4.0</summary>

## [0.4.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-google-group-v0.3.0...foundation-google-group-v0.4.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
</details>

<details><summary>foundation-hierarchical-firewall-policy: 0.4.0</summary>

## [0.4.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-hierarchical-firewall-policy-v0.3.0...foundation-hierarchical-firewall-policy-v0.4.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
</details>

<details><summary>foundation-instance-template: 0.6.0</summary>

## [0.6.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-instance-template-v0.5.1...foundation-instance-template-v0.6.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* update instance template Go structs for 5-app-infra gaps ([#70](https://github.com/VitruvianSoftware/vitruvian-core/issues/70)) ([34fef73](https://github.com/VitruvianSoftware/vitruvian-core/commit/34fef73736390e7816a177d31a098d516f725666))
</details>

<details><summary>foundation-kms: 0.4.0</summary>

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
</details>

<details><summary>foundation-network: 0.4.0</summary>

## [0.4.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-network-v0.3.0...foundation-network-v0.4.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
</details>

<details><summary>foundation-network-peering: 0.4.0</summary>

## [0.4.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-network-peering-v0.3.0...foundation-network-peering-v0.4.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
</details>

<details><summary>foundation-org-policy: 0.4.0</summary>

## [0.4.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-org-policy-v0.3.2...foundation-org-policy-v0.4.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **ts/psc:** add support for target, noAutomateDnsZone, and serviceDirectoryRegistrations ([#65](https://github.com/VitruvianSoftware/vitruvian-core/issues/65)) ([8a3d9b1](https://github.com/VitruvianSoftware/vitruvian-core/commit/8a3d9b170214d2296cfbb9d8764841fffc6d954a))
</details>

<details><summary>foundation-parent-iam: 0.4.0</summary>

## [0.4.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-parent-iam-v0.3.0...foundation-parent-iam-v0.4.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
</details>

<details><summary>foundation-private-service-connect: 0.4.0</summary>

## [0.4.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-private-service-connect-v0.3.2...foundation-private-service-connect-v0.4.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **ts/psc:** add support for target, noAutomateDnsZone, and serviceDirectoryRegistrations ([#65](https://github.com/VitruvianSoftware/vitruvian-core/issues/65)) ([8a3d9b1](https://github.com/VitruvianSoftware/vitruvian-core/commit/8a3d9b170214d2296cfbb9d8764841fffc6d954a))
</details>

<details><summary>foundation-project-factory: 0.5.0</summary>

## [0.5.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-project-factory-v0.4.1...foundation-project-factory-v0.5.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **ts/project-factory:** implement disable/delete for defaultServiceAccount ([#62](https://github.com/VitruvianSoftware/vitruvian-core/issues/62)) ([138a86e](https://github.com/VitruvianSoftware/vitruvian-core/commit/138a86ebd180ee70e25193cd62563eca083f641b))
</details>

<details><summary>foundation-simple-bucket: 0.4.0</summary>

## [0.4.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-simple-bucket-v0.3.0...foundation-simple-bucket-v0.4.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
</details>

<details><summary>foundation-vpn-ha: 0.5.0</summary>

## [0.5.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-vpn-ha-v0.4.0...foundation-vpn-ha-v0.5.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* Phase 7 component parity ([#75](https://github.com/VitruvianSoftware/vitruvian-core/issues/75)) ([8e2647e](https://github.com/VitruvianSoftware/vitruvian-core/commit/8e2647e6d2b1f5312aea5d892339779dc8c97b4f))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
</details>

<details><summary>foundation-vpc-service-controls: 0.4.0</summary>

## [0.4.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-vpc-service-controls-v0.3.0...foundation-vpc-service-controls-v0.4.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
</details>

<details><summary>foundation-cai-monitoring: 0.3.0</summary>

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-cai-monitoring-v0.2.0...foundation-cai-monitoring-v0.3.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
</details>

<details><summary>foundation-bootstrap: 0.3.0</summary>

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-bootstrap-v0.2.1...foundation-bootstrap-v0.3.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **bootstrap:** always enable impersonation APIs on the seed project ([6502dd4](https://github.com/VitruvianSoftware/vitruvian-core/commit/6502dd4823d4f1cb76899c2bcce16ee681574725))
* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **ts/centralized-logging:** stop clobbering linkedDatasetName ([f0926e8](https://github.com/VitruvianSoftware/vitruvian-core/commit/f0926e87f57ba78daaebfd51f680607b444aca73))
</details>

<details><summary>foundation-cloud-dns: 0.3.0</summary>

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-cloud-dns-v0.2.0...foundation-cloud-dns-v0.3.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
</details>

<details><summary>foundation-cloud-functions: 0.3.0</summary>

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-cloud-functions-v0.2.0...foundation-cloud-functions-v0.3.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
</details>

<details><summary>foundation-cloud-router: 0.3.0</summary>

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-cloud-router-v0.2.0...foundation-cloud-router-v0.3.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
</details>

<details><summary>foundation-cloud-storage: 0.3.0</summary>

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-cloud-storage-v0.2.0...foundation-cloud-storage-v0.3.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
</details>

<details><summary>foundation-compute-instance: 0.3.0</summary>

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-compute-instance-v0.2.1...foundation-compute-instance-v0.3.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* update instance template Go structs for 5-app-infra gaps ([#70](https://github.com/VitruvianSoftware/vitruvian-core/issues/70)) ([34fef73](https://github.com/VitruvianSoftware/vitruvian-core/commit/34fef73736390e7816a177d31a098d516f725666))
</details>

<details><summary>foundation-gcloud: 0.3.0</summary>

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcloud-v0.2.0...foundation-gcloud-v0.3.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
</details>

<details><summary>foundation-log-export: 0.3.0</summary>

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-log-export-v0.2.0...foundation-log-export-v0.3.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
</details>

<details><summary>foundation-network-firewall-policy: 0.3.0</summary>

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-network-firewall-policy-v0.2.0...foundation-network-firewall-policy-v0.3.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
</details>

<details><summary>foundation-pubsub: 0.3.0</summary>

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-pubsub-v0.2.0...foundation-pubsub-v0.3.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate TypeScript packages into the pnpm workspace ([8896936](https://github.com/VitruvianSoftware/vitruvian-core/commit/8896936dd10224cf47503de7a6d8f7212e0f1c03))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
</details>

<details><summary>go-app: 0.5.0</summary>

## [0.5.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-app-v0.4.2...go-app-v0.5.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate Go modules into the Bazel workspace ([b95e735](https://github.com/VitruvianSoftware/vitruvian-core/commit/b95e735574f373a9f08a31acb453ae6508ccc0b3))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **pulumi/library:** satisfy conformance-check (canonical versions) ([6b73b37](https://github.com/VitruvianSoftware/vitruvian-core/commit/6b73b37b832ad1e6f5dd2ba1cfe0d2dc0aefd0bf))
* **tests:** fix library tests struct types ([#71](https://github.com/VitruvianSoftware/vitruvian-core/issues/71)) ([a51a2d8](https://github.com/VitruvianSoftware/vitruvian-core/commit/a51a2d8d805248ffef72d6c4529d17139ac33aeb))
</details>

<details><summary>go-bootstrap: 2.0.0</summary>

## [2.0.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-bootstrap-v1.0.1...go-bootstrap-v2.0.0) (2026-07-06)


###   BREAKING CHANGES

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
</details>

<details><summary>go-cicd: 0.5.0</summary>

## [0.5.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-cicd-v0.4.2...go-cicd-v0.5.0) (2026-07-06)


### Features

* **cicd:** map attribute.environment for per-GitHub-Environment WIF scoping ([#608](https://github.com/VitruvianSoftware/vitruvian-core/issues/608)) ([6cde30e](https://github.com/VitruvianSoftware/vitruvian-core/commit/6cde30ed103fef6d0c3bfe60ba21036acc786a5f))
* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate Go modules into the Bazel workspace ([b95e735](https://github.com/VitruvianSoftware/vitruvian-core/commit/b95e735574f373a9f08a31acb453ae6508ccc0b3))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/cicd:** add repository_owner to WIF attribute mapping ([#67](https://github.com/VitruvianSoftware/vitruvian-core/issues/67)) ([eb2ab57](https://github.com/VitruvianSoftware/vitruvian-core/commit/eb2ab57d58a93e4cbd12688d5cba493c7f015a26))
* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **pulumi/library:** satisfy conformance-check (canonical versions) ([6b73b37](https://github.com/VitruvianSoftware/vitruvian-core/commit/6b73b37b832ad1e6f5dd2ba1cfe0d2dc0aefd0bf))
* **tests:** fix library tests struct types ([#71](https://github.com/VitruvianSoftware/vitruvian-core/issues/71)) ([a51a2d8](https://github.com/VitruvianSoftware/vitruvian-core/commit/a51a2d8d805248ffef72d6c4529d17139ac33aeb))
</details>

<details><summary>go-data: 0.5.0</summary>

## [0.5.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-data-v0.4.2...go-data-v0.5.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate Go modules into the Bazel workspace ([b95e735](https://github.com/VitruvianSoftware/vitruvian-core/commit/b95e735574f373a9f08a31acb453ae6508ccc0b3))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **pulumi/library:** satisfy conformance-check (canonical versions) ([6b73b37](https://github.com/VitruvianSoftware/vitruvian-core/commit/6b73b37b832ad1e6f5dd2ba1cfe0d2dc0aefd0bf))
* **tests:** fix library tests struct types ([#71](https://github.com/VitruvianSoftware/vitruvian-core/issues/71)) ([a51a2d8](https://github.com/VitruvianSoftware/vitruvian-core/commit/a51a2d8d805248ffef72d6c4529d17139ac33aeb))
</details>

<details><summary>go-iam: 0.5.0</summary>

## [0.5.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-iam-v0.4.2...go-iam-v0.5.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate Go modules into the Bazel workspace ([b95e735](https://github.com/VitruvianSoftware/vitruvian-core/commit/b95e735574f373a9f08a31acb453ae6508ccc0b3))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library/iam:** remove duplicate nil-checks (nogo nilness) ([d703e33](https://github.com/VitruvianSoftware/vitruvian-core/commit/d703e3311de97f4ba0c47f16e21154a8692520dc))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **pulumi/library:** satisfy conformance-check (canonical versions) ([6b73b37](https://github.com/VitruvianSoftware/vitruvian-core/commit/6b73b37b832ad1e6f5dd2ba1cfe0d2dc0aefd0bf))
* **tests:** fix library tests struct types ([#71](https://github.com/VitruvianSoftware/vitruvian-core/issues/71)) ([a51a2d8](https://github.com/VitruvianSoftware/vitruvian-core/commit/a51a2d8d805248ffef72d6c4529d17139ac33aeb))
</details>

<details><summary>go-cloud-dns: 0.3.0</summary>

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-cloud-dns-v0.2.2...go-cloud-dns-v0.3.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate Go modules into the Bazel workspace ([b95e735](https://github.com/VitruvianSoftware/vitruvian-core/commit/b95e735574f373a9f08a31acb453ae6508ccc0b3))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **pulumi/library:** satisfy conformance-check (canonical versions) ([6b73b37](https://github.com/VitruvianSoftware/vitruvian-core/commit/6b73b37b832ad1e6f5dd2ba1cfe0d2dc0aefd0bf))
* **tests:** fix library tests struct types ([#71](https://github.com/VitruvianSoftware/vitruvian-core/issues/71)) ([a51a2d8](https://github.com/VitruvianSoftware/vitruvian-core/commit/a51a2d8d805248ffef72d6c4529d17139ac33aeb))
</details>

<details><summary>go-cloud-functions: 0.3.0</summary>

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-cloud-functions-v0.2.2...go-cloud-functions-v0.3.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate Go modules into the Bazel workspace ([b95e735](https://github.com/VitruvianSoftware/vitruvian-core/commit/b95e735574f373a9f08a31acb453ae6508ccc0b3))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **pulumi/library:** satisfy conformance-check (canonical versions) ([6b73b37](https://github.com/VitruvianSoftware/vitruvian-core/commit/6b73b37b832ad1e6f5dd2ba1cfe0d2dc0aefd0bf))
* **tests:** fix library tests struct types ([#71](https://github.com/VitruvianSoftware/vitruvian-core/issues/71)) ([a51a2d8](https://github.com/VitruvianSoftware/vitruvian-core/commit/a51a2d8d805248ffef72d6c4529d17139ac33aeb))
</details>

<details><summary>go-cloud-router: 0.3.0</summary>

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-cloud-router-v0.2.2...go-cloud-router-v0.3.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate Go modules into the Bazel workspace ([b95e735](https://github.com/VitruvianSoftware/vitruvian-core/commit/b95e735574f373a9f08a31acb453ae6508ccc0b3))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **pulumi/library:** satisfy conformance-check (canonical versions) ([6b73b37](https://github.com/VitruvianSoftware/vitruvian-core/commit/6b73b37b832ad1e6f5dd2ba1cfe0d2dc0aefd0bf))
* **tests:** fix library tests struct types ([#71](https://github.com/VitruvianSoftware/vitruvian-core/issues/71)) ([a51a2d8](https://github.com/VitruvianSoftware/vitruvian-core/commit/a51a2d8d805248ffef72d6c4529d17139ac33aeb))
</details>

<details><summary>go-compute-instance: 0.3.0</summary>

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-compute-instance-v0.2.3...go-compute-instance-v0.3.0) (2026-07-06)


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
</details>

<details><summary>go-gcloud: 0.3.0</summary>

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-gcloud-v0.2.2...go-gcloud-v0.3.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate Go modules into the Bazel workspace ([b95e735](https://github.com/VitruvianSoftware/vitruvian-core/commit/b95e735574f373a9f08a31acb453ae6508ccc0b3))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **pulumi/library:** satisfy conformance-check (canonical versions) ([6b73b37](https://github.com/VitruvianSoftware/vitruvian-core/commit/6b73b37b832ad1e6f5dd2ba1cfe0d2dc0aefd0bf))
* **tests:** fix library tests struct types ([#71](https://github.com/VitruvianSoftware/vitruvian-core/issues/71)) ([a51a2d8](https://github.com/VitruvianSoftware/vitruvian-core/commit/a51a2d8d805248ffef72d6c4529d17139ac33aeb))
</details>

<details><summary>go-instance-template: 0.3.0</summary>

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
</details>

<details><summary>go-kms: 0.3.0</summary>

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-kms-v0.2.2...go-kms-v0.3.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate Go modules into the Bazel workspace ([b95e735](https://github.com/VitruvianSoftware/vitruvian-core/commit/b95e735574f373a9f08a31acb453ae6508ccc0b3))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **pulumi/library:** satisfy conformance-check (canonical versions) ([6b73b37](https://github.com/VitruvianSoftware/vitruvian-core/commit/6b73b37b832ad1e6f5dd2ba1cfe0d2dc0aefd0bf))
* **tests:** fix library tests struct types ([#71](https://github.com/VitruvianSoftware/vitruvian-core/issues/71)) ([a51a2d8](https://github.com/VitruvianSoftware/vitruvian-core/commit/a51a2d8d805248ffef72d6c4529d17139ac33aeb))
</details>

<details><summary>go-log-export: 0.3.0</summary>

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-log-export-v0.2.2...go-log-export-v0.3.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate Go modules into the Bazel workspace ([b95e735](https://github.com/VitruvianSoftware/vitruvian-core/commit/b95e735574f373a9f08a31acb453ae6508ccc0b3))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **pulumi/library:** satisfy conformance-check (canonical versions) ([6b73b37](https://github.com/VitruvianSoftware/vitruvian-core/commit/6b73b37b832ad1e6f5dd2ba1cfe0d2dc0aefd0bf))
* **tests:** fix library tests struct types ([#71](https://github.com/VitruvianSoftware/vitruvian-core/issues/71)) ([a51a2d8](https://github.com/VitruvianSoftware/vitruvian-core/commit/a51a2d8d805248ffef72d6c4529d17139ac33aeb))
</details>

<details><summary>go-network-firewall-policy: 0.3.0</summary>

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-network-firewall-policy-v0.2.2...go-network-firewall-policy-v0.3.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate Go modules into the Bazel workspace ([b95e735](https://github.com/VitruvianSoftware/vitruvian-core/commit/b95e735574f373a9f08a31acb453ae6508ccc0b3))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **pulumi/library:** satisfy conformance-check (canonical versions) ([6b73b37](https://github.com/VitruvianSoftware/vitruvian-core/commit/6b73b37b832ad1e6f5dd2ba1cfe0d2dc0aefd0bf))
* **tests:** fix library tests struct types ([#71](https://github.com/VitruvianSoftware/vitruvian-core/issues/71)) ([a51a2d8](https://github.com/VitruvianSoftware/vitruvian-core/commit/a51a2d8d805248ffef72d6c4529d17139ac33aeb))
</details>

<details><summary>go-network-peering: 0.4.0</summary>

## [0.4.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-network-peering-v0.3.0...go-network-peering-v0.4.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate Go modules into the Bazel workspace ([b95e735](https://github.com/VitruvianSoftware/vitruvian-core/commit/b95e735574f373a9f08a31acb453ae6508ccc0b3))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))
* **pulumi/library:** multi-package publish-on-version-bump + corrected export transforms ([#598](https://github.com/VitruvianSoftware/vitruvian-core/issues/598)) ([ba92a6b](https://github.com/VitruvianSoftware/vitruvian-core/commit/ba92a6b0d709e21bae78e1f3ef844cc1c5f4e16b))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** forward-port published features the graft missed + reconcile manifest ([#597](https://github.com/VitruvianSoftware/vitruvian-core/issues/597)) ([7f43cec](https://github.com/VitruvianSoftware/vitruvian-core/commit/7f43cecd822d7b7abf480f037389a55c64d0b25c))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **pulumi/library:** satisfy conformance-check (canonical versions) ([6b73b37](https://github.com/VitruvianSoftware/vitruvian-core/commit/6b73b37b832ad1e6f5dd2ba1cfe0d2dc0aefd0bf))
* **tests:** fix library tests struct types ([#71](https://github.com/VitruvianSoftware/vitruvian-core/issues/71)) ([a51a2d8](https://github.com/VitruvianSoftware/vitruvian-core/commit/a51a2d8d805248ffef72d6c4529d17139ac33aeb))
</details>

<details><summary>go-private-service-connect: 0.3.0</summary>

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-private-service-connect-v0.2.2...go-private-service-connect-v0.3.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate Go modules into the Bazel workspace ([b95e735](https://github.com/VitruvianSoftware/vitruvian-core/commit/b95e735574f373a9f08a31acb453ae6508ccc0b3))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **pulumi/library:** satisfy conformance-check (canonical versions) ([6b73b37](https://github.com/VitruvianSoftware/vitruvian-core/commit/6b73b37b832ad1e6f5dd2ba1cfe0d2dc0aefd0bf))
* **tests:** fix library tests struct types ([#71](https://github.com/VitruvianSoftware/vitruvian-core/issues/71)) ([a51a2d8](https://github.com/VitruvianSoftware/vitruvian-core/commit/a51a2d8d805248ffef72d6c4529d17139ac33aeb))
</details>

<details><summary>go-pubsub: 0.3.0</summary>

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/go-pubsub-v0.2.2...go-pubsub-v0.3.0) (2026-07-06)


### Features

* graft pulumi-library into monorepo (history-preserving) ([39571e5](https://github.com/VitruvianSoftware/vitruvian-core/commit/39571e5e558e8492a0bcc366b5f4576bb0867118))
* **pulumi/library:** integrate Go modules into the Bazel workspace ([b95e735](https://github.com/VitruvianSoftware/vitruvian-core/commit/b95e735574f373a9f08a31acb453ae6508ccc0b3))
* **pulumi/library:** migrate pulumi-library into the monorepo (PR1) ([da77f88](https://github.com/VitruvianSoftware/vitruvian-core/commit/da77f88e7ce7db43f343b1b98bab4db0e0727090))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **pulumi/library:** gazelle-exclude subtree; defer TS Bazel targets ([3cfa7d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cfa7d7841d01549585f3a29e7337a1826f0a0b4))
* **pulumi/library:** npm_package targets + format-clean the subtree ([71ee99c](https://github.com/VitruvianSoftware/vitruvian-core/commit/71ee99c2b1353a01f780cbd18f15140bdf79fdb3))
* **pulumi/library:** prettier-format the subtree to monorepo style ([57e0b5e](https://github.com/VitruvianSoftware/vitruvian-core/commit/57e0b5e6c4ee72bb9b85897049f56ba269efae05))
* **pulumi/library:** satisfy conformance-check (canonical versions) ([6b73b37](https://github.com/VitruvianSoftware/vitruvian-core/commit/6b73b37b832ad1e6f5dd2ba1cfe0d2dc0aefd0bf))
* **tests:** fix library tests struct types ([#71](https://github.com/VitruvianSoftware/vitruvian-core/issues/71)) ([a51a2d8](https://github.com/VitruvianSoftware/vitruvian-core/commit/a51a2d8d805248ffef72d6c4529d17139ac33aeb))
</details>

<details><summary>1.0.1</summary>

## [1.0.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/v1.0.2...v1.0.1) (2026-07-06)


###   BREAKING CHANGES

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
</details>

<details><summary>1.0.1</summary>

## [1.0.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/v1.1.0...v1.0.1) (2026-07-06)


###   BREAKING CHANGES

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
</details>

<details><summary>1.0.1</summary>

## [1.0.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/v1.0.2...v1.0.1) (2026-07-06)


###   BREAKING CHANGES

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
</details>

<details><summary>1.0.1</summary>

## [1.0.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/v1.0.2...v1.0.1) (2026-07-06)


###   BREAKING CHANGES

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
</details>

<details><summary>1.0.1</summary>

## [1.0.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/v1.0.2...v1.0.1) (2026-07-06)


###   BREAKING CHANGES

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
</details>

<details><summary>1.0.1</summary>

## [1.0.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/v1.0.2...v1.0.1) (2026-07-06)


###   BREAKING CHANGES

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
</details>

<details><summary>1.0.1</summary>

## [1.0.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/v1.0.2...v1.0.1) (2026-07-06)


###   BREAKING CHANGES

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
</details>

<details><summary>1.0.1</summary>

## [1.0.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/v1.0.2...v1.0.1) (2026-07-06)


###   BREAKING CHANGES

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
</details>

---
This PR was generated with [Release Please](https://github.com/googleapis/release-please). See [documentation](https://github.com/googleapis/release-please#release-please).