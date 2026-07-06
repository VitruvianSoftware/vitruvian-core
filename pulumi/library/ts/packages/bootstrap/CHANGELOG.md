# Changelog

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

## [0.2.1](https://github.com/VitruvianSoftware/pulumi-library/compare/foundation-bootstrap-v0.2.0...foundation-bootstrap-v0.2.1) (2026-07-04)

### Bug Fixes

- **bootstrap:** always enable impersonation APIs on the seed project ([8063653](https://github.com/VitruvianSoftware/pulumi-library/commit/806365320fa047980cd307c163aa92d1a7be81a9))
- **ts/centralized-logging:** stop clobbering linkedDatasetName ([b0189b2](https://github.com/VitruvianSoftware/pulumi-library/commit/b0189b2d6c3b5c7b70dd2e6294b237778ef8cb10))

## [0.2.0](https://github.com/VitruvianSoftware/pulumi-library/compare/foundation-bootstrap-v0.1.0...foundation-bootstrap-v0.2.0) (2026-05-06)

### Features

- add 22 fine-grained library packages for foundation modular parity ([#48](https://github.com/VitruvianSoftware/pulumi-library/issues/48)) ([f54c6f2](https://github.com/VitruvianSoftware/pulumi-library/commit/f54c6f2a30ea4429a69e31ad3168aa3f075b0070))

### Bug Fixes

- **ts:** trigger release ([1bcb6fa](https://github.com/VitruvianSoftware/pulumi-library/commit/1bcb6faa91d8c2bb7d6b80c6ec1e081bf8e136b6))
