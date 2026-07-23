# Changelog

## [1.9.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-projects-v1.8.0...foundation-gcp-projects-v1.9.0) (2026-07-23)


### Features

* **gcp-projects:** foundation owns the oauth-user-inspector build space (adopt) ([#1086](https://github.com/VitruvianSoftware/vitruvian-core/issues/1086)) ([e2525c7](https://github.com/VitruvianSoftware/vitruvian-core/commit/e2525c742fbf9fe803bb308d6e0ab00bfb3523b0))

## [1.8.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-projects-v1.7.0...foundation-gcp-projects-v1.8.0) (2026-07-23)


### Features

* **gcp-projects:** mint the bu2 app-infra pipeline identity (sa-app-infra-bu2) ([#1078](https://github.com/VitruvianSoftware/vitruvian-core/issues/1078)) ([42c62c9](https://github.com/VitruvianSoftware/vitruvian-core/commit/42c62c9464b6cc09fdb79815021dece76b0aa363))

## [1.7.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-projects-v1.6.0...foundation-gcp-projects-v1.7.0) (2026-07-22)


### Features

* **gcp-projects:** env leaves grant the BU pipeline SA artifact-registry reader ([#1057](https://github.com/VitruvianSoftware/vitruvian-core/issues/1057)) ([928ae6b](https://github.com/VitruvianSoftware/vitruvian-core/commit/928ae6b4eee4bd509382d2f3a43156e85c5a3cb0))

## [1.6.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-projects-v1.5.1...foundation-gcp-projects-v1.6.0) (2026-07-22)


### Features

* **gcp-projects:** foundation-owned app build space (AR repo + build identity) ([#1055](https://github.com/VitruvianSoftware/vitruvian-core/issues/1055)) ([8e6aa7b](https://github.com/VitruvianSoftware/vitruvian-core/commit/8e6aa7b20886137ba5c7599de9b9cb7828c0c62e))

## [1.5.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-projects-v1.5.0...foundation-gcp-projects-v1.5.1) (2026-07-22)


### Bug Fixes

* **gcp-projects:** enable Secret Manager on the shared infra-pipeline project ([#1022](https://github.com/VitruvianSoftware/vitruvian-core/issues/1022)) ([692f76c](https://github.com/VitruvianSoftware/vitruvian-core/commit/692f76c69d20b4b7754d2b4eaa6ea9ecd3a6454f))

## [1.5.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-projects-v1.4.1...foundation-gcp-projects-v1.5.0) (2026-07-21)


### Features

* **foundation:** issue a BU app-infra pipeline identity and ungate stage 5 ([#1008](https://github.com/VitruvianSoftware/vitruvian-core/issues/1008)) ([7892f92](https://github.com/VitruvianSoftware/vitruvian-core/commit/7892f92687e812190de59bf322a4b9aec02541b6))

## [1.4.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-projects-v1.4.0...foundation-gcp-projects-v1.4.1) (2026-07-21)


### Bug Fixes

* **gcp-projects:** correct the deploy SA description after the stage relocation ([#1000](https://github.com/VitruvianSoftware/vitruvian-core/issues/1000)) ([ab0ea1a](https://github.com/VitruvianSoftware/vitruvian-core/commit/ab0ea1a4ebcc98757d22306e6d76f47a3b223413))

## [1.4.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-projects-v1.3.4...foundation-gcp-projects-v1.4.0) (2026-07-21)


### Features

* **gcp-projects:** add business_unit_2 for tabula's dedicated per-env projects ([#973](https://github.com/VitruvianSoftware/vitruvian-core/issues/973)) ([1215ec6](https://github.com/VitruvianSoftware/vitruvian-core/commit/1215ec6f9d078a02a7bd8e27815e7c81198edd60))

## [1.3.4](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-projects-v1.3.3...foundation-gcp-projects-v1.3.4) (2026-07-20)


### Bug Fixes

* **oauth-user-inspector:** per-env Site Verification SELF-verify; remove owner delegation entirely ([#956](https://github.com/VitruvianSoftware/vitruvian-core/issues/956)) ([66cbdfd](https://github.com/VitruvianSoftware/vitruvian-core/commit/66cbdfdf34b57109fc4653dc7873e67172abd6f4))

## [1.3.3](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-projects-v1.3.2...foundation-gcp-projects-v1.3.3) (2026-07-19)


### Bug Fixes

* **oauth-user-inspector:** shorten Cloudflare TXT comment (&lt;=100) + document siteverification console-only enable ([#953](https://github.com/VitruvianSoftware/vitruvian-core/issues/953)) ([fc27e38](https://github.com/VitruvianSoftware/vitruvian-core/commit/fc27e38b1fe48095515c955cd16882eb4713a45f))

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
