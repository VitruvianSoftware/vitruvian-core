# Changelog

## [0.3.15](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-networks-v0.3.14...foundation-gcp-networks-v0.3.15) (2026-07-24)


### Bug Fixes

* **foundation:** close two audit findings — region guard gap + inert SCC key ([#1128](https://github.com/VitruvianSoftware/vitruvian-core/issues/1128)) ([cbd3cff](https://github.com/VitruvianSoftware/vitruvian-core/commit/cbd3cff51355407ee1783487389dae2b35b314dc))

## [0.3.14](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-networks-v0.3.13...foundation-gcp-networks-v0.3.14) (2026-07-24)


### Bug Fixes

* **gcp-networks:** consume region from bootstrap; secondary us-south1 → us-west1 ([#1122](https://github.com/VitruvianSoftware/vitruvian-core/issues/1122)) ([3e7e1c6](https://github.com/VitruvianSoftware/vitruvian-core/commit/3e7e1c63f121b1c8d0d882d4c8460170e5940f6f))

## [0.3.13](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-networks-v0.3.12...foundation-gcp-networks-v0.3.13) (2026-07-24)


### Bug Fixes

* **gcp-networks:** sort subnet exports for deterministic ordering ([#1111](https://github.com/VitruvianSoftware/vitruvian-core/issues/1111)) ([719e153](https://github.com/VitruvianSoftware/vitruvian-core/commit/719e1538f9bb136f1801030ad04f0a43a2e0011e))

## [0.3.12](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-networks-v0.3.11...foundation-gcp-networks-v0.3.12) (2026-07-23)


### Bug Fixes

* **examples:** region-consume in the app-infra example + compile it in CI ([#1100](https://github.com/VitruvianSoftware/vitruvian-core/issues/1100)) ([3e98243](https://github.com/VitruvianSoftware/vitruvian-core/commit/3e9824361ee566c82477747c4db7763d7e316ee8))

## [0.3.11](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-networks-v0.3.10...foundation-gcp-networks-v0.3.11) (2026-07-18)


### Bug Fixes

* **foundation:** drop temp local replaces, pin published pulumi-library versions ([#915](https://github.com/VitruvianSoftware/vitruvian-core/issues/915)) ([946c3ba](https://github.com/VitruvianSoftware/vitruvian-core/commit/946c3ba8f0e98806dcacaaee778df6929819e5a9))

## [0.3.10](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-networks-v0.3.9...foundation-gcp-networks-v0.3.10) (2026-07-10)


### Bug Fixes

* **networks:** put VPC-SC bridge members in dry-run Spec (not enforced Status) ([#846](https://github.com/VitruvianSoftware/vitruvian-core/issues/846)) ([89a592f](https://github.com/VitruvianSoftware/vitruvian-core/commit/89a592ffe1bf96a215eeeae524966dd1fa131207))

## [0.3.9](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-networks-v0.3.8...foundation-gcp-networks-v0.3.9) (2026-07-10)


### Bug Fixes

* **networks:** consume network/v2 v2.0.3 (transitivity delete-ordering fix) ([#838](https://github.com/VitruvianSoftware/vitruvian-core/issues/838)) ([ec39eba](https://github.com/VitruvianSoftware/vitruvian-core/commit/ec39eba8ee3bf81073bbde1ac352ef33e6a60b9a))

## [0.3.8](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-networks-v0.3.7...foundation-gcp-networks-v0.3.8) (2026-07-10)


### Bug Fixes

* **networks:** consume network/v2 v2.0.2 (transitivity perpetual-replace fix) ([#797](https://github.com/VitruvianSoftware/vitruvian-core/issues/797)) ([1269417](https://github.com/VitruvianSoftware/vitruvian-core/commit/1269417196c0330787976fcaa2a145a1fe05bf6f))

## [0.3.7](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-networks-v0.3.6...foundation-gcp-networks-v0.3.7) (2026-07-09)


### Bug Fixes

* **networks:** set vpc_sc_members so VPC-SC access levels are valid ([#777](https://github.com/VitruvianSoftware/vitruvian-core/issues/777)) ([151bc32](https://github.com/VitruvianSoftware/vitruvian-core/commit/151bc326594e1e85fafc24490541a2fe374b1473))

## [0.3.6](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-networks-v0.3.5...foundation-gcp-networks-v0.3.6) (2026-07-09)


### Bug Fixes

* **networks:** stop nil-pointer panic when exporting subnet secondary ranges ([#772](https://github.com/VitruvianSoftware/vitruvian-core/issues/772)) ([7646175](https://github.com/VitruvianSoftware/vitruvian-core/commit/76461754478e88e1e370aae28c04bbc3a1fa8433))

## [0.3.5](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-networks-v0.3.4...foundation-gcp-networks-v0.3.5) (2026-07-09)


### Bug Fixes

* remediate 16 foundation audit findings for upstream parity ([#758](https://github.com/VitruvianSoftware/vitruvian-core/issues/758)) ([82aff7f](https://github.com/VitruvianSoftware/vitruvian-core/commit/82aff7f2b5c6bbf0cf3b2559825133b85e0b2ee0))

## [0.3.4](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-networks-v0.3.3...foundation-gcp-networks-v0.3.4) (2026-07-09)


### Bug Fixes

* **networks:** chain network routing dependencies to fix race conditions ([0ff0f53](https://github.com/VitruvianSoftware/vitruvian-core/commit/0ff0f53d267b5a46ec6e2a19bcdc20292858fe96))

## [0.3.3](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-networks-v0.3.2...foundation-gcp-networks-v0.3.3) (2026-07-08)


### Bug Fixes

* **networks:** add hub VPC dependency to spoke peering and DNS zones ([09f1c67](https://github.com/VitruvianSoftware/vitruvian-core/commit/09f1c67eb0dcb86b29883d30d70147206399503d))
* **networks:** bump go/pkg/network to v1.2.0 for PSC name fix ([44e052d](https://github.com/VitruvianSoftware/vitruvian-core/commit/44e052df6f24f32b8dfd302c0aa7a884b535dd12))
* **networks:** bump go/pkg/network to v1.2.1 for transitivity balancing mode fix ([dafc114](https://github.com/VitruvianSoftware/vitruvian-core/commit/dafc114ca291dc149f84fdcfbab10baa25893c82))
* **networks:** bump go/pkg/network to v1.2.2 for PrivateIpGoogleAccess fix ([2ae7ad0](https://github.com/VitruvianSoftware/vitruvian-core/commit/2ae7ad0509d3eb9d19356420f28ace5625aa565b))
* **networks:** fix compilation errors from previous commit ([fa4ba12](https://github.com/VitruvianSoftware/vitruvian-core/commit/fa4ba124f2dc07df6c3d84907b6b991a6f12f472))
* **networks:** use dynamic hubProjectID to fix DNS peering target ([4fe85c6](https://github.com/VitruvianSoftware/vitruvian-core/commit/4fe85c669db6feb50ed54d2e33eaa9b8025b6b1e))

## [0.3.2](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-networks-v0.3.1...foundation-gcp-networks-v0.3.2) (2026-07-08)


### Bug Fixes

* **networks:** remove duplicate compute import ([6d91533](https://github.com/VitruvianSoftware/vitruvian-core/commit/6d91533c1dacd465c9cbc90ff3bb5edeaf57d54f))

## [0.3.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-networks-v0.3.0...foundation-gcp-networks-v0.3.1) (2026-07-08)


### Bug Fixes

* **networks:** use fully-qualified folder resource name for parent_id ([#747](https://github.com/VitruvianSoftware/vitruvian-core/issues/747)) ([e9e63ec](https://github.com/VitruvianSoftware/vitruvian-core/commit/e9e63ec2cad6ad4d0cbe45b04f5ee4194acfc6ca))

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-networks-v0.2.1...foundation-gcp-networks-v0.3.0) (2026-07-08)


### Features

* add foundation phase 3 — hub-and-spoke networks (gcp-networks) ([#732](https://github.com/VitruvianSoftware/vitruvian-core/issues/732)) ([efdefab](https://github.com/VitruvianSoftware/vitruvian-core/commit/efdefab4ae809c2731811f16e517716ff12d4e9d))
* **gcp-bootstrap:** trigger release ([550e1df](https://github.com/VitruvianSoftware/vitruvian-core/commit/550e1dffdb3525781923eb4f3369050dd77c5aec))
* **gcp-org:** trigger release ([3bb4b9e](https://github.com/VitruvianSoftware/vitruvian-core/commit/3bb4b9efab7fa9a8c59a9d68966d6f4c252fa89f))
* **org-folders:** trigger release ([588230c](https://github.com/VitruvianSoftware/vitruvian-core/commit/588230c68cc864fa77efd6324dc40c511e1ba0c7))


### Bug Fixes

* **ci:** split target-determinator bazel-opts to fix fail-open sweeps ([#744](https://github.com/VitruvianSoftware/vitruvian-core/issues/744)) ([60a642a](https://github.com/VitruvianSoftware/vitruvian-core/commit/60a642a3eca5b91877c82668cdbf13ad0b5679c5))
* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **networks:** correct Shared VPC Hub configuration ([#736](https://github.com/VitruvianSoftware/vitruvian-core/issues/736)) ([ac181ee](https://github.com/VitruvianSoftware/vitruvian-core/commit/ac181ee9a6fa72ebd97771299c4ee446ed20e8c4))
* **networks:** restore upstream shared VPC host pattern ([#741](https://github.com/VitruvianSoftware/vitruvian-core/issues/741)) ([d6aa81f](https://github.com/VitruvianSoftware/vitruvian-core/commit/d6aa81fe8c2e8c9ac5a9cfc5cd3efbdccf2a5e3a))

## [0.2.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-networks-v0.2.0...foundation-gcp-networks-v0.2.1) (2026-07-08)


### Bug Fixes

* **networks:** correct Shared VPC Hub configuration ([#736](https://github.com/VitruvianSoftware/vitruvian-core/issues/736)) ([ac181ee](https://github.com/VitruvianSoftware/vitruvian-core/commit/ac181ee9a6fa72ebd97771299c4ee446ed20e8c4))
* **networks:** restore upstream shared VPC host pattern ([#741](https://github.com/VitruvianSoftware/vitruvian-core/issues/741)) ([d6aa81f](https://github.com/VitruvianSoftware/vitruvian-core/commit/d6aa81fe8c2e8c9ac5a9cfc5cd3efbdccf2a5e3a))

## [0.2.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-networks-v0.1.0...foundation-gcp-networks-v0.2.0) (2026-07-08)


### Features

* add foundation phase 3 — hub-and-spoke networks (gcp-networks) ([#732](https://github.com/VitruvianSoftware/vitruvian-core/issues/732)) ([efdefab](https://github.com/VitruvianSoftware/vitruvian-core/commit/efdefab4ae809c2731811f16e517716ff12d4e9d))
* **gcp-bootstrap:** trigger release ([550e1df](https://github.com/VitruvianSoftware/vitruvian-core/commit/550e1dffdb3525781923eb4f3369050dd77c5aec))
* **gcp-org:** trigger release ([3bb4b9e](https://github.com/VitruvianSoftware/vitruvian-core/commit/3bb4b9efab7fa9a8c59a9d68966d6f4c252fa89f))
* **org-folders:** trigger release ([588230c](https://github.com/VitruvianSoftware/vitruvian-core/commit/588230c68cc864fa77efd6324dc40c511e1ba0c7))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
