# Changelog

## [0.13.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.12.0...foundation-gcp-bootstrap-v0.13.0) (2026-08-19)


### Features

* **foundation:** federate the homelab cluster with GCP, keylessly ([#1781](https://github.com/VitruvianSoftware/vitruvian-core/issues/1781)) ([5d56276](https://github.com/VitruvianSoftware/vitruvian-core/commit/5d56276b4a92e6eca25589d1df6acf9f9b0bc223))

## [0.12.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.11.1...foundation-gcp-bootstrap-v0.12.0) (2026-08-04)


### Features

* **billing:** fund gcp-networks' 4 host projects from personal billing ([#1376](https://github.com/VitruvianSoftware/vitruvian-core/issues/1376)) ([7d2cc6a](https://github.com/VitruvianSoftware/vitruvian-core/commit/7d2cc6a7230a2d484434e7c1c667db73997cbd76))

## [0.11.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.11.0...foundation-gcp-bootstrap-v0.11.1) (2026-07-27)


### Bug Fixes

* **deps:** bump klauspost/compress to v1.18.7 (GO-2026-5841) — unwedges the merge queue ([#1268](https://github.com/VitruvianSoftware/vitruvian-core/issues/1268)) ([338f365](https://github.com/VitruvianSoftware/vitruvian-core/commit/338f365b0f84b328c0bf880ca0ebb4595590b8bd))

## [0.11.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.10.2...foundation-gcp-bootstrap-v0.11.0) (2026-07-27)


### Features

* **foundation:** give the ESC identity org-level rights, and stop it impersonating silently ([#1255](https://github.com/VitruvianSoftware/vitruvian-core/issues/1255)) ([b7a05ec](https://github.com/VitruvianSoftware/vitruvian-core/commit/b7a05ecfe1af6a80376d152ce9eb43eac4389979))

## [0.10.2](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.10.1...foundation-gcp-bootstrap-v0.10.2) (2026-07-26)


### Bug Fixes

* **foundation:** let the bootstrap SA write the org policy this stage declares ([#1251](https://github.com/VitruvianSoftware/vitruvian-core/issues/1251)) ([4d92a36](https://github.com/VitruvianSoftware/vitruvian-core/commit/4d92a36ec6bf02b8961ad70849d74a135e1f4950))

## [0.10.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.10.0...foundation-gcp-bootstrap-v0.10.1) (2026-07-26)


### Bug Fixes

* **foundation:** allow the Pulumi issuer in the WIF org policy, and build that allowlist once ([#1247](https://github.com/VitruvianSoftware/vitruvian-core/issues/1247)) ([b396a73](https://github.com/VitruvianSoftware/vitruvian-core/commit/b396a7332ac8b3f15f1e196e643be265acf341aa))

## [0.10.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.9.0...foundation-gcp-bootstrap-v0.10.0) (2026-07-26)


### Features

* **foundation:** create the Pulumi ESC environment in code, and harden the account check ([#1245](https://github.com/VitruvianSoftware/vitruvian-core/issues/1245)) ([ba59a8b](https://github.com/VitruvianSoftware/vitruvian-core/commit/ba59a8b0761d86fd6c67a354b43a8aa79d37b267))

## [0.9.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.8.2...foundation-gcp-bootstrap-v0.9.0) (2026-07-26)


### Features

* keyless GCP via Pulumi ESC federation, and BUILDBUDDY_API_KEY as environment-only ([#1242](https://github.com/VitruvianSoftware/vitruvian-core/issues/1242)) ([440cbfb](https://github.com/VitruvianSoftware/vitruvian-core/commit/440cbfbf6442544a0ecb2ccd5456fc23cf74bc2f))

## [0.8.2](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.8.1...foundation-gcp-bootstrap-v0.8.2) (2026-07-24)


### Bug Fixes

* **gcp-bootstrap:** projects SA needs billing.projectManager to re-assign billing ([#1135](https://github.com/VitruvianSoftware/vitruvian-core/issues/1135)) ([3397e6f](https://github.com/VitruvianSoftware/vitruvian-core/commit/3397e6facc201fded81619f6a429005b9f2cf578))

## [0.8.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.8.0...foundation-gcp-bootstrap-v0.8.1) (2026-07-24)


### Bug Fixes

* **gcp-bootstrap:** projects SA needs serviceUsageAdmin, not just Consumer ([#1118](https://github.com/VitruvianSoftware/vitruvian-core/issues/1118)) ([c262b40](https://github.com/VitruvianSoftware/vitruvian-core/commit/c262b405afee013babf178032aac125796cb42d2))

## [0.8.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.7.0...foundation-gcp-bootstrap-v0.8.0) (2026-07-21)


### Features

* **foundation:** issue a BU app-infra pipeline identity and ungate stage 5 ([#1008](https://github.com/VitruvianSoftware/vitruvian-core/issues/1008)) ([7892f92](https://github.com/VitruvianSoftware/vitruvian-core/commit/7892f92687e812190de59bf322a4b9aec02541b6))

## [0.7.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.6.1...foundation-gcp-bootstrap-v0.7.0) (2026-07-21)


### Features

* **gcp-app-infra:** add the live foundation stage 5 and adopt the app deploy identity ([#995](https://github.com/VitruvianSoftware/vitruvian-core/issues/995)) ([e631130](https://github.com/VitruvianSoftware/vitruvian-core/commit/e63113009aa39d409b9e1e3db7d20b11dc6d4b92))

## [0.6.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.6.0...foundation-gcp-bootstrap-v0.6.1) (2026-07-18)


### Bug Fixes

* **foundation:** drop temp local replaces, pin published pulumi-library versions ([#915](https://github.com/VitruvianSoftware/vitruvian-core/issues/915)) ([946c3ba](https://github.com/VitruvianSoftware/vitruvian-core/commit/946c3ba8f0e98806dcacaaee778df6929819e5a9))

## [0.6.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.5.0...foundation-gcp-bootstrap-v0.6.0) (2026-07-11)


### Features

* **foundation:** WIF repo-pin + proj-SA folder grants (stage-5 bootstrap prereqs) ([#865](https://github.com/VitruvianSoftware/vitruvian-core/issues/865)) ([21d7370](https://github.com/VitruvianSoftware/vitruvian-core/commit/21d737051dfec8b9f2f43ee71a0f0549bd12eb45))

## [0.5.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.4.4...foundation-gcp-bootstrap-v0.5.0) (2026-07-10)


### Features

* **foundation:** provision proj-stage WIF bindings + GitHub environments (stage-4 CI enablement) ([#802](https://github.com/VitruvianSoftware/vitruvian-core/issues/802)) ([335371c](https://github.com/VitruvianSoftware/vitruvian-core/commit/335371c19282e77161036d2edae5e26209d6d523))

## [0.4.4](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.4.3...foundation-gcp-bootstrap-v0.4.4) (2026-07-09)


### Bug Fixes

* **foundation:** deterministically order seed/cicd label updates behind the projects.update grant ([#768](https://github.com/VitruvianSoftware/vitruvian-core/issues/768)) ([0a12386](https://github.com/VitruvianSoftware/vitruvian-core/commit/0a123866bd100bb66a474c78d033ee9f9fee1585))
* **foundation:** widen bootstrap projects.update propagation gate to 300s ([#770](https://github.com/VitruvianSoftware/vitruvian-core/issues/770)) ([f6b9759](https://github.com/VitruvianSoftware/vitruvian-core/commit/f6b9759692b353e416e3563c6a36f1cc04cfd537))
* **gcp-bootstrap:** pin cloudidentity provider project to stop preview drift ([#771](https://github.com/VitruvianSoftware/vitruvian-core/issues/771)) ([0b4e40d](https://github.com/VitruvianSoftware/vitruvian-core/commit/0b4e40d502c6c4b086760edf0aa1dd5b8dfd18ab))

## [0.4.3](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.4.2...foundation-gcp-bootstrap-v0.4.3) (2026-07-09)


### Bug Fixes

* **foundation:** make projects.update remediation fully CI-deployable (org+env SAs + bootstrap self-mints custom role) ([#765](https://github.com/VitruvianSoftware/vitruvian-core/issues/765)) ([2b8e90d](https://github.com/VitruvianSoftware/vitruvian-core/commit/2b8e90d42e7d4128a44b53e895499a3a96e56260))

## [0.4.2](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.4.1...foundation-gcp-bootstrap-v0.4.2) (2026-07-09)


### Bug Fixes

* **foundation:** grant bootstrap SA resourcemanager.projects.update for label upkeep ([#763](https://github.com/VitruvianSoftware/vitruvian-core/issues/763)) ([e0eba1e](https://github.com/VitruvianSoftware/vitruvian-core/commit/e0eba1e55eb091b04951280a1bc089d07ff0c100))

## [0.4.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.4.0...foundation-gcp-bootstrap-v0.4.1) (2026-07-09)


### Bug Fixes

* remediate 16 foundation audit findings for upstream parity ([#758](https://github.com/VitruvianSoftware/vitruvian-core/issues/758)) ([82aff7f](https://github.com/VitruvianSoftware/vitruvian-core/commit/82aff7f2b5c6bbf0cf3b2559825133b85e0b2ee0))

## [0.4.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.3.6...foundation-gcp-bootstrap-v0.4.0) (2026-07-08)


### Features

* add foundation phase 3 — hub-and-spoke networks (gcp-networks) ([#732](https://github.com/VitruvianSoftware/vitruvian-core/issues/732)) ([efdefab](https://github.com/VitruvianSoftware/vitruvian-core/commit/efdefab4ae809c2731811f16e517716ff12d4e9d))

## [0.3.6](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.3.5...foundation-gcp-bootstrap-v0.3.6) (2026-07-08)


### Bug Fixes

* **bootstrap:** add per-environment WIF bindings for environments stage ([#729](https://github.com/VitruvianSoftware/vitruvian-core/issues/729)) ([3bab9aa](https://github.com/VitruvianSoftware/vitruvian-core/commit/3bab9aa7b5aa36cdd40171844e62c6cb39085361))

## [0.3.5](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.3.4...foundation-gcp-bootstrap-v0.3.5) (2026-07-08)


### Bug Fixes

* **gcp-org:** add DependsOn for BigQuery dataset to wait for API enablement ([#714](https://github.com/VitruvianSoftware/vitruvian-core/issues/714)) ([c21b093](https://github.com/VitruvianSoftware/vitruvian-core/commit/c21b093c4ea96a386e0eb376a1007491a3bb7f18))

## [0.3.4](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.3.3...foundation-gcp-bootstrap-v0.3.4) (2026-07-08)


### Bug Fixes

* **ci:** re-enable foundation preview workflows ([#713](https://github.com/VitruvianSoftware/vitruvian-core/issues/713)) ([c681d75](https://github.com/VitruvianSoftware/vitruvian-core/commit/c681d759b4fceb9a0f944961ca652253b33a585e))
* **pulumi-library:** decouple API enablement dependency ([#651](https://github.com/VitruvianSoftware/vitruvian-core/issues/651)) ([6a03698](https://github.com/VitruvianSoftware/vitruvian-core/commit/6a036986759a76888dbe279ce53f46ab3f8f5968))

## [0.3.3](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.3.2...foundation-gcp-bootstrap-v0.3.3) (2026-07-07)


### Bug Fixes

* **foundation:** grant serviceUsageAdmin to bootstrap SA on seed project ([#649](https://github.com/VitruvianSoftware/vitruvian-core/issues/649)) ([76de6b9](https://github.com/VitruvianSoftware/vitruvian-core/commit/76de6b9e2d414f85d83791ddb27a60654cde07e4))

## [0.3.2](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.3.1...foundation-gcp-bootstrap-v0.3.2) (2026-07-07)


### Bug Fixes

* **ci:** isolate release-please config/manifest per foundation phase ([#644](https://github.com/VitruvianSoftware/vitruvian-core/issues/644)) ([1764a59](https://github.com/VitruvianSoftware/vitruvian-core/commit/1764a596793c232280341a8d4b1f4572894cac64))
* **foundation:** enable orgpolicy.googleapis.com on seed project ([#648](https://github.com/VitruvianSoftware/vitruvian-core/issues/648)) ([26cc978](https://github.com/VitruvianSoftware/vitruvian-core/commit/26cc978139b4d76d5e09edbbe6e882cbefae121b))

## [0.3.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.3.0...foundation-gcp-bootstrap-v0.3.1) (2026-07-07)


### Bug Fixes

* **ci:** give each foundation phase its own environment and remove shared concurrency ([#642](https://github.com/VitruvianSoftware/vitruvian-core/issues/642)) ([05ee6ad](https://github.com/VitruvianSoftware/vitruvian-core/commit/05ee6ad6a7f271ac038bbe06000e273c6f3f8ae2))

## [0.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/foundation-gcp-bootstrap-v0.2.0...foundation-gcp-bootstrap-v0.3.0) (2026-07-07)


### Features

* automate foundation deployment via github actions ([#634](https://github.com/VitruvianSoftware/vitruvian-core/issues/634)) ([7fb5e4b](https://github.com/VitruvianSoftware/vitruvian-core/commit/7fb5e4ba818d79dd00a8bf7c77267b1a21b82e40))
* **foundation:** dedicated Cloud Identity quota project (replace sandbox anchor) ([#618](https://github.com/VitruvianSoftware/vitruvian-core/issues/618)) ([566b9dc](https://github.com/VitruvianSoftware/vitruvian-core/commit/566b9dcefd51e2611f55690c55434becf94b6a50))
* **foundation:** monorepo-native GCP bootstrap for vitruviansoftware.dev ([#612](https://github.com/VitruvianSoftware/vitruvian-core/issues/612)) ([ba352b5](https://github.com/VitruvianSoftware/vitruvian-core/commit/ba352b5b48bf28cb0688ba5dedee05aaac8e0ff6))
* **gcp-bootstrap:** trigger release ([550e1df](https://github.com/VitruvianSoftware/vitruvian-core/commit/550e1dffdb3525781923eb4f3369050dd77c5aec))
* **gcp-org:** trigger release ([3bb4b9e](https://github.com/VitruvianSoftware/vitruvian-core/commit/3bb4b9efab7fa9a8c59a9d68966d6f4c252fa89f))
* **org-folders:** trigger release ([588230c](https://github.com/VitruvianSoftware/vitruvian-core/commit/588230c68cc864fa77efd6324dc40c511e1ba0c7))


### Bug Fixes

* **foundation:** bootstrap polish before 1-org — deterministic bucket IAM + API-propagation wait ([#620](https://github.com/VitruvianSoftware/vitruvian-core/issues/620)) ([c41629f](https://github.com/VitruvianSoftware/vitruvian-core/commit/c41629fcbc38cc5dea1cf039b3885b0242de5a1e))
* **foundation:** codify Cloud Identity quota project for group creation ([#614](https://github.com/VitruvianSoftware/vitruvian-core/issues/614)) ([0ce3557](https://github.com/VitruvianSoftware/vitruvian-core/commit/0ce35578315b69fc465490bd557a35bd2ceb0e84))
* **foundation:** folder-scoped WIF issuer org-policy exception ([#616](https://github.com/VitruvianSoftware/vitruvian-core/issues/616)) ([ebb3e8a](https://github.com/VitruvianSoftware/vitruvian-core/commit/ebb3e8aebe2635ae0a6ce5ce5b8cffbbc1aeb796))
* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
