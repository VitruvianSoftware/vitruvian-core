# Changelog

## [1.3.2](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-projects-v1.3.1...foundation-gcp-projects-v1.3.2) (2026-07-19)


### Bug Fixes

* **foundation:** enable siteverification on the DEV oss floating project via the project factory ([#950](https://github.com/VitruvianSoftware/vitruvian-core/issues/950)) ([dadf4f5](https://github.com/VitruvianSoftware/vitruvian-core/commit/dadf4f551be75f59c0d535de2b322327e465afe9))

## [1.3.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-projects-v1.3.0...foundation-gcp-projects-v1.3.1) (2026-07-19)


### Bug Fixes

* **oauth-user-inspector:** app-scope the custom-domain verification (drop the [#938](https://github.com/VitruvianSoftware/vitruvian-core/issues/938) foundation coupling) ([#946](https://github.com/VitruvianSoftware/vitruvian-core/issues/946)) ([cd5f316](https://github.com/VitruvianSoftware/vitruvian-core/commit/cd5f3161ce62c0eca5ed2ec9ecd34f7199a159bf))

## [1.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-projects-v1.2.4...foundation-gcp-projects-v1.3.0) (2026-07-19)


### Features

* **oauth-user-inspector:** automate custom-domain ownership verification for DomainMappings ([#938](https://github.com/VitruvianSoftware/vitruvian-core/issues/938)) ([f5a75b4](https://github.com/VitruvianSoftware/vitruvian-core/commit/f5a75b4a5e6c7d4a587a9753d2bc5fe17fdb6517))

## [1.2.4](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-projects-v1.2.3...foundation-gcp-projects-v1.2.4) (2026-07-18)


### Bug Fixes

* **foundation:** drop temp local replaces, pin published pulumi-library versions ([#915](https://github.com/VitruvianSoftware/vitruvian-core/issues/915)) ([946c3ba](https://github.com/VitruvianSoftware/vitruvian-core/commit/946c3ba8f0e98806dcacaaee778df6929819e5a9))

## [1.2.3](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-projects-v1.2.2...foundation-gcp-projects-v1.2.3) (2026-07-11)


### Bug Fixes

* **gcp-projects:** address upstream-fidelity findings from the 4-projects review ([#889](https://github.com/VitruvianSoftware/vitruvian-core/issues/889)) ([2ca876a](https://github.com/VitruvianSoftware/vitruvian-core/commit/2ca876a4dc7df2206608acef3a356fab0bc71e54))

## [1.2.2](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-projects-v1.2.1...foundation-gcp-projects-v1.2.2) (2026-07-11)


### Bug Fixes

* **gcp-projects:** disable default compute SA (match upstream), not deprivilege ([#883](https://github.com/VitruvianSoftware/vitruvian-core/issues/883)) ([9662226](https://github.com/VitruvianSoftware/vitruvian-core/commit/9662226c9ee5fafb9f79e51610bb5b15322f4758))

## [1.2.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-projects-v1.2.0...foundation-gcp-projects-v1.2.1) (2026-07-11)


### Bug Fixes

* **gcp-projects:** populate the CMEK `keys` export (was always empty) ([#877](https://github.com/VitruvianSoftware/vitruvian-core/issues/877)) ([9daa856](https://github.com/VitruvianSoftware/vitruvian-core/commit/9daa856baa1058cfe2f15bc2eecc5d2e7211c55e))

## [1.2.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-projects-v1.1.0...foundation-gcp-projects-v1.2.0) (2026-07-11)


### Features

* **foundation:** stage-5 app-tier APIs + infra-pipeline + exports (fix infra_pipeline_project_id port bug) ([#866](https://github.com/VitruvianSoftware/vitruvian-core/issues/866)) ([a1a8495](https://github.com/VitruvianSoftware/vitruvian-core/commit/a1a8495c922adf41de7416f0b50aa30708a47a26))

## [1.1.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-projects-v1.0.0...foundation-gcp-projects-v1.1.0) (2026-07-10)


### Features

* **foundation:** add OSS floating project (prj-{env}-bu1-oss-floating) ([#854](https://github.com/VitruvianSoftware/vitruvian-core/issues/854)) ([8fb12e7](https://github.com/VitruvianSoftware/vitruvian-core/commit/8fb12e7ad95e711e864e17398369d20caa91748d))

## 1.0.0 (2026-07-10)


### Features

* **foundation:** live stage 4 gcp-projects (bu1 floating, co-tenant under fldr-foundation-1) ([#795](https://github.com/VitruvianSoftware/vitruvian-core/issues/795)) ([2eaffae](https://github.com/VitruvianSoftware/vitruvian-core/commit/2eaffaea49373afe207c6f6899ed0970762c3875))
* **foundation:** wire gcp-projects (stage 4) into the CI/CD pipeline ([#849](https://github.com/VitruvianSoftware/vitruvian-core/issues/849)) ([bfca0d1](https://github.com/VitruvianSoftware/vitruvian-core/commit/bfca0d12c7dc0dd64b6ffc40f6c17ecbd5ee3192))
* **gcp-bootstrap:** trigger release ([550e1df](https://github.com/VitruvianSoftware/vitruvian-core/commit/550e1dffdb3525781923eb4f3369050dd77c5aec))
* **gcp-org:** trigger release ([3bb4b9e](https://github.com/VitruvianSoftware/vitruvian-core/commit/3bb4b9efab7fa9a8c59a9d68966d6f4c252fa89f))
* **org-folders:** trigger release ([588230c](https://github.com/VitruvianSoftware/vitruvian-core/commit/588230c68cc864fa77efd6324dc40c511e1ba0c7))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
