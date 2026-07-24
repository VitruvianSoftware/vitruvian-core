# Changelog

## [0.6.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-org-v0.6.0...foundation-gcp-org-v0.6.1) (2026-07-24)


### Bug Fixes

* **foundation:** close two audit findings — region guard gap + inert SCC key ([#1128](https://github.com/VitruvianSoftware/vitruvian-core/issues/1128)) ([cbd3cff](https://github.com/VitruvianSoftware/vitruvian-core/commit/cbd3cff51355407ee1783487389dae2b35b314dc))

## [0.6.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-org-v0.5.1...foundation-gcp-org-v0.6.0) (2026-07-21)


### Features

* **tabula:** repoint CI identity at the bu2 projects + allow public invoker ([#978](https://github.com/VitruvianSoftware/vitruvian-core/issues/978)) ([ab04390](https://github.com/VitruvianSoftware/vitruvian-core/commit/ab04390d3c71860a8581eeea75be4907d70d42c5))

## [0.5.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-org-v0.5.0...foundation-gcp-org-v0.5.1) (2026-07-18)


### Bug Fixes

* **foundation:** drop temp local replaces, pin published pulumi-library versions ([#915](https://github.com/VitruvianSoftware/vitruvian-core/issues/915)) ([946c3ba](https://github.com/VitruvianSoftware/vitruvian-core/commit/946c3ba8f0e98806dcacaaee778df6929819e5a9))

## [0.5.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-org-v0.4.5...foundation-gcp-org-v0.5.0) (2026-07-11)


### Features

* **foundation:** DRS override permitting public invoker on the OSS projects ([#867](https://github.com/VitruvianSoftware/vitruvian-core/issues/867)) ([b4e9cdf](https://github.com/VitruvianSoftware/vitruvian-core/commit/b4e9cdfe24956a182d7c7a6d4eb786e64f652bb4))

## [0.4.5](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-org-v0.4.4...foundation-gcp-org-v0.4.5) (2026-07-10)


### Bug Fixes

* **org:** export per-env network project NUMBERS for VPC-SC ([#841](https://github.com/VitruvianSoftware/vitruvian-core/issues/841)) ([1ef71c7](https://github.com/VitruvianSoftware/vitruvian-core/commit/1ef71c7b9495da5ae02b84f18959d2362bf87a39))

## [0.4.4](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-org-v0.4.3...foundation-gcp-org-v0.4.4) (2026-07-09)


### Bug Fixes

* **gcp-org:** own the org ACM policy (enable create_access_context_manager_policy) ([#775](https://github.com/VitruvianSoftware/vitruvian-core/issues/775)) ([713c8b4](https://github.com/VitruvianSoftware/vitruvian-core/commit/713c8b432ed74c2e1a723194bab95665ce92615c))

## [0.4.3](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-org-v0.4.2...foundation-gcp-org-v0.4.3) (2026-07-09)


### Bug Fixes

* remediate 16 foundation audit findings for upstream parity ([#758](https://github.com/VitruvianSoftware/vitruvian-core/issues/758)) ([82aff7f](https://github.com/VitruvianSoftware/vitruvian-core/commit/82aff7f2b5c6bbf0cf3b2559825133b85e0b2ee0))

## [0.4.2](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-org-v0.4.1...foundation-gcp-org-v0.4.2) (2026-07-08)


### Bug Fixes

* **networks:** restore upstream shared VPC host pattern ([#741](https://github.com/VitruvianSoftware/vitruvian-core/issues/741)) ([d6aa81f](https://github.com/VitruvianSoftware/vitruvian-core/commit/d6aa81fe8c2e8c9ac5a9cfc5cd3efbdccf2a5e3a))

## [0.4.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-org-v0.4.0...foundation-gcp-org-v0.4.1) (2026-07-08)


### Bug Fixes

* **networks:** correct Shared VPC Hub configuration ([#736](https://github.com/VitruvianSoftware/vitruvian-core/issues/736)) ([ac181ee](https://github.com/VitruvianSoftware/vitruvian-core/commit/ac181ee9a6fa72ebd97771299c4ee446ed20e8c4))

## [0.4.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-org-v0.3.3...foundation-gcp-org-v0.4.0) (2026-07-08)


### Features

* **gcp-org:** enable hub and spoke network topology ([#722](https://github.com/VitruvianSoftware/vitruvian-core/issues/722)) ([9a0d398](https://github.com/VitruvianSoftware/vitruvian-core/commit/9a0d398d774a93db2b6518e5faea16b85583effd))

## [0.3.3](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-org-v0.3.2...foundation-gcp-org-v0.3.3) (2026-07-08)


### Bug Fixes

* **gcp-org:** disable Access Context Manager policy creation ([#719](https://github.com/VitruvianSoftware/vitruvian-core/issues/719)) ([67cc97b](https://github.com/VitruvianSoftware/vitruvian-core/commit/67cc97ba238d449172aa68045a1e943a065b049b))

## [0.3.2](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-org-v0.3.1...foundation-gcp-org-v0.3.2) (2026-07-08)


### Bug Fixes

* **gcp-org:** use Cloud Identity customer ID for domain-restricted sharing ([#717](https://github.com/VitruvianSoftware/vitruvian-core/issues/717)) ([296377d](https://github.com/VitruvianSoftware/vitruvian-core/commit/296377d47b819310385c16bf32c71564cd68913e))

## [0.3.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-org-v0.3.0...foundation-gcp-org-v0.3.1) (2026-07-08)


### Bug Fixes

* **gcp-org:** add DependsOn for BigQuery dataset to wait for API enablement ([#714](https://github.com/VitruvianSoftware/vitruvian-core/issues/714)) ([c21b093](https://github.com/VitruvianSoftware/vitruvian-core/commit/c21b093c4ea96a386e0eb376a1007491a3bb7f18))

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-org-v0.2.0...foundation-gcp-org-v0.3.0) (2026-07-07)


### Features

* **foundation:** add monorepo-native gcp-org (Phase 1 Organization) ([#631](https://github.com/VitruvianSoftware/vitruvian-core/issues/631)) ([faaa2bd](https://github.com/VitruvianSoftware/vitruvian-core/commit/faaa2bd615beb496a98d2b8bf3e41f9b883b78e0))
* **gcp-bootstrap:** trigger release ([550e1df](https://github.com/VitruvianSoftware/vitruvian-core/commit/550e1dffdb3525781923eb4f3369050dd77c5aec))
* **gcp-org:** trigger release ([3bb4b9e](https://github.com/VitruvianSoftware/vitruvian-core/commit/3bb4b9efab7fa9a8c59a9d68966d6f4c252fa89f))
* **org-folders:** trigger release ([588230c](https://github.com/VitruvianSoftware/vitruvian-core/commit/588230c68cc864fa77efd6324dc40c511e1ba0c7))


### Bug Fixes

* **ci:** isolate release-please config/manifest per foundation phase ([#644](https://github.com/VitruvianSoftware/vitruvian-core/issues/644)) ([1764a59](https://github.com/VitruvianSoftware/vitruvian-core/commit/1764a596793c232280341a8d4b1f4572894cac64))
* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
