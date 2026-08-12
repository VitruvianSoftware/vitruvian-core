# Changelog

<!--
Maintained by release-please (oauth-user-inspector/release-please-config.json).
Entries are generated from conventional-commit subjects touching this directory
on main; do not hand-edit released sections. The 1.0.0 block below predates that
adoption and is kept verbatim as the app's history — it sat under an
`[Unreleased]` heading, unchanged, for 69 commits.
-->

## [1.5.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/oauth-user-inspector-v1.4.1...oauth-user-inspector-v1.5.0) (2026-08-12)


### Features

* **oauth-user-inspector:** complete design system migration across all components ([#1548](https://github.com/VitruvianSoftware/vitruvian-core/issues/1548)) ([bb2dfc3](https://github.com/VitruvianSoftware/vitruvian-core/commit/bb2dfc38b85d39a4b8fed8a74e2738ab0b1313f3))

## [1.4.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/oauth-user-inspector-v1.4.0...oauth-user-inspector-v1.4.1) (2026-08-11)


### Bug Fixes

* **oauth-user-inspector:** make design system components self-contained for standalone Docker build ([#1544](https://github.com/VitruvianSoftware/vitruvian-core/issues/1544)) ([67462c2](https://github.com/VitruvianSoftware/vitruvian-core/commit/67462c2758f05c1e3c272c117e18ed27b82f87c7))

## [1.4.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/oauth-user-inspector-v1.3.0...oauth-user-inspector-v1.4.0) (2026-08-11)


### Features

* **oauth-user-inspector:** adopt @vitruviansoftware/design-system components and tokens ([#1542](https://github.com/VitruvianSoftware/vitruvian-core/issues/1542)) ([6b6b865](https://github.com/VitruvianSoftware/vitruvian-core/commit/6b6b865e2242ad7b1e21708e2085a44586b623e2))

## [1.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/oauth-user-inspector-v1.2.0...oauth-user-inspector-v1.3.0) (2026-07-25)


### Features

* **devx:** dogfood devx.yaml, add local-dev index, fix agent-skill links ([#1154](https://github.com/VitruvianSoftware/vitruvian-core/issues/1154)) ([4e3d73d](https://github.com/VitruvianSoftware/vitruvian-core/commit/4e3d73da5270f30e538db165917c8403428cad4c))

## [1.2.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/oauth-user-inspector-v1.1.1...oauth-user-inspector-v1.2.0) (2026-07-23)


### Features

* **gcp-projects:** foundation owns the oauth build space in us-central1; strip the app build stack ([#1107](https://github.com/VitruvianSoftware/vitruvian-core/issues/1107)) ([c8e6d08](https://github.com/VitruvianSoftware/vitruvian-core/commit/c8e6d086e76f8a89573bafd250d94b452569a7a1))

## [1.1.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/oauth-user-inspector-v1.1.0...oauth-user-inspector-v1.1.1) (2026-07-21)


### Bug Fixes

* **release:** keep co-located &lt;app&gt;/infra out of the app's release unit ([#1006](https://github.com/VitruvianSoftware/vitruvian-core/issues/1006)) ([eadfa39](https://github.com/VitruvianSoftware/vitruvian-core/commit/eadfa39280589eedb62b6b267a31859d9506884c))

## [1.1.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/oauth-user-inspector-v1.0.1...oauth-user-inspector-v1.1.0) (2026-07-21)


### Features

* **gcp-app-infra:** add the live foundation stage 5 and adopt the app deploy identity ([#995](https://github.com/VitruvianSoftware/vitruvian-core/issues/995)) ([e631130](https://github.com/VitruvianSoftware/vitruvian-core/commit/e63113009aa39d409b9e1e3db7d20b11dc6d4b92))

## [1.0.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/oauth-user-inspector-v1.0.0...oauth-user-inspector-v1.0.1) (2026-07-21)


### Bug Fixes

* **oauth-user-inspector:** make the deploy panel show what is actually shipping ([#971](https://github.com/VitruvianSoftware/vitruvian-core/issues/971)) ([93283b4](https://github.com/VitruvianSoftware/vitruvian-core/commit/93283b451827284edbb818ba975b28cdcf90ea18))

## 1.0.0 (2026-06-25)

### Added

* Vendored OAuth User Inspector into the `vitruvian-core` monorepo, with the
  VitruvianSoftware MIT license header applied across the source tree and the
  standard governance files (CLA, Code of Conduct, License).
