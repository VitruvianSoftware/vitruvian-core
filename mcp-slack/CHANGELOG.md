# Changelog

## [1.10.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/mcp-slack-v1.10.0...mcp-slack-v1.10.1) (2026-08-21)


### Bug Fixes

* **npm:** declare the repository fields sigstore provenance requires ([#1865](https://github.com/VitruvianSoftware/vitruvian-core/issues/1865)) ([ea9991a](https://github.com/VitruvianSoftware/vitruvian-core/commit/ea9991ac627956ad28ca7bf026ef200765f0fa9a)), closes [#1511](https://github.com/VitruvianSoftware/vitruvian-core/issues/1511)

## [1.10.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/mcp-slack-v1.9.0...mcp-slack-v1.10.0) (2026-08-21)


### Features

* **release:** publish to npm via trusted publishing (OIDC), not a token ([#1862](https://github.com/VitruvianSoftware/vitruvian-core/issues/1862)) ([b99da72](https://github.com/VitruvianSoftware/vitruvian-core/commit/b99da729080022d14a66671cd4d05de61cae4bef))

## [1.9.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/mcp-slack-v1.8.3...mcp-slack-v1.9.0) (2026-08-17)


### Features

* **backstage:** render mermaid diagrams in TechDocs ([#1710](https://github.com/VitruvianSoftware/vitruvian-core/issues/1710)) ([00666bd](https://github.com/VitruvianSoftware/vitruvian-core/commit/00666bd24c1a265239e1befd4a8993c392d087aa))

## [1.8.3](https://github.com/VitruvianSoftware/vitruvian-core/compare/mcp-slack-v1.8.2...mcp-slack-v1.8.3) (2026-08-17)


### Bug Fixes

* **backstage:** make TechDocs work for every component ([#1700](https://github.com/VitruvianSoftware/vitruvian-core/issues/1700)) ([26c6aa7](https://github.com/VitruvianSoftware/vitruvian-core/commit/26c6aa7c2953877a116bd59413b0a1d07e5f9e51))

## [1.8.2](https://github.com/VitruvianSoftware/vitruvian-core/compare/mcp-slack-v1.8.1...mcp-slack-v1.8.2) (2026-08-08)


### Bug Fixes

* **mcp-slack:** publish npm releases again — nine tags shipped nothing ([#1498](https://github.com/VitruvianSoftware/vitruvian-core/issues/1498)) ([150a8dd](https://github.com/VitruvianSoftware/vitruvian-core/commit/150a8ddef3cad8d8495ded0dd28ac667df55f124))

## [1.8.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/mcp-slack-v1.8.0...mcp-slack-v1.8.1) (2026-08-08)


### Bug Fixes

* **mcp-slack:** make chart appVersion track the app, not drift from it ([#1489](https://github.com/VitruvianSoftware/vitruvian-core/issues/1489)) ([ea938b4](https://github.com/VitruvianSoftware/vitruvian-core/commit/ea938b403799e8ab6ce6c2b08501279f1697814c))

## [1.8.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/mcp-slack-v1.7.0...mcp-slack-v1.8.0) (2026-08-08)


### Features

* **mcp-slack:** L3/L4 egress policy — bounds lateral movement, not exfiltration ([#1487](https://github.com/VitruvianSoftware/vitruvian-core/issues/1487)) ([89229b6](https://github.com/VitruvianSoftware/vitruvian-core/commit/89229b67c326b2b1971d685cbffc4bcf4a713280))

## [1.7.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/mcp-slack-v1.6.0...mcp-slack-v1.7.0) (2026-08-07)


### Features

* **mcp-slack:** Phase 2b deployment chart, scoped project, and 5xx alert ([#1420](https://github.com/VitruvianSoftware/vitruvian-core/issues/1420)) ([58601fa](https://github.com/VitruvianSoftware/vitruvian-core/commit/58601fa53e25140fe614addcf3b8cef5bb7a994b))

## [1.6.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/mcp-slack-v1.5.0...mcp-slack-v1.6.0) (2026-08-07)


### Features

* **mcp-slack:** record refused callers instead of only answering them ([#1429](https://github.com/VitruvianSoftware/vitruvian-core/issues/1429)) ([329a49d](https://github.com/VitruvianSoftware/vitruvian-core/commit/329a49d5e4796305bcf80bb1f86e9283a07f757b))

## [1.5.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/mcp-slack-v1.4.0...mcp-slack-v1.5.0) (2026-08-07)


### Features

* **mcp-slack:** require an explicit subject allow-list on the HTTP transport ([#1424](https://github.com/VitruvianSoftware/vitruvian-core/issues/1424)) ([600fc26](https://github.com/VitruvianSoftware/vitruvian-core/commit/600fc269d81a426ec2987c39a7d6827d4382ddc7))

## [1.4.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/mcp-slack-v1.3.0...mcp-slack-v1.4.0) (2026-08-07)


### Features

* **mcp-slack:** drain in-flight requests on SIGTERM ([#1423](https://github.com/VitruvianSoftware/vitruvian-core/issues/1423)) ([1b476b3](https://github.com/VitruvianSoftware/vitruvian-core/commit/1b476b3be2afc8d8fa7363231e010d5cad656588))

## [1.3.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/mcp-slack-v1.2.0...mcp-slack-v1.3.0) (2026-08-07)


### Features

* **mcp-slack:** declare channel visibility separately from the allow-list ([#1421](https://github.com/VitruvianSoftware/vitruvian-core/issues/1421)) ([87a202d](https://github.com/VitruvianSoftware/vitruvian-core/commit/87a202d9a24df13a5a26357a98953f640a16f16e))

## [1.2.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/mcp-slack-v1.1.0...mcp-slack-v1.2.0) (2026-08-07)


### Features

* **mcp-slack:** Streamable HTTP transport with OAuth and channel allow-list ([#1418](https://github.com/VitruvianSoftware/vitruvian-core/issues/1418)) ([11c8f8d](https://github.com/VitruvianSoftware/vitruvian-core/commit/11c8f8dfc06743b8961c4e639e98fc8231280f4e))

## [1.1.0](https://github.com/VitruvianSoftware/vitruvian-core/compare/mcp-slack-v1.0.3...mcp-slack-v1.1.0) (2026-07-10)


### Features

* **build:** close the inter-app visibility firewall + conformance guard ([#82](https://github.com/VitruvianSoftware/vitruvian-core/issues/82)) ([#496](https://github.com/VitruvianSoftware/vitruvian-core/issues/496)) ([30e8a09](https://github.com/VitruvianSoftware/vitruvian-core/commit/30e8a09bfb2c19b1602e522f222ea518ca8e210a))
* **deploy:** per-app metadata catalog + reusable _deploy-cloud-run.yaml + tabula de-race ([#500](https://github.com/VitruvianSoftware/vitruvian-core/issues/500), [#499](https://github.com/VitruvianSoftware/vitruvian-core/issues/499)) ([#511](https://github.com/VitruvianSoftware/vitruvian-core/issues/511)) ([d546651](https://github.com/VitruvianSoftware/vitruvian-core/commit/d5466512896c9aa691cdff8e1d3016798cb3cd88))
* **gcp-bootstrap:** trigger release ([550e1df](https://github.com/VitruvianSoftware/vitruvian-core/commit/550e1dffdb3525781923eb4f3369050dd77c5aec))
* **gcp-org:** trigger release ([3bb4b9e](https://github.com/VitruvianSoftware/vitruvian-core/commit/3bb4b9efab7fa9a8c59a9d68966d6f4c252fa89f))
* **org-folders:** trigger release ([588230c](https://github.com/VitruvianSoftware/vitruvian-core/commit/588230c68cc864fa77efd6324dc40c511e1ba0c7))


### Bug Fixes

* **go/logging:** grant bucketWriter for log-bucket destination ([#63](https://github.com/VitruvianSoftware/vitruvian-core/issues/63)) ([1388d02](https://github.com/VitruvianSoftware/vitruvian-core/commit/1388d02c2314a775443713c0ad070bc5afd44826))
* **license:** enforce MIT + VitruvianSoftware (content gate) and relicense ([#477](https://github.com/VitruvianSoftware/vitruvian-core/issues/477)) ([639aaa0](https://github.com/VitruvianSoftware/vitruvian-core/commit/639aaa0750e9882b1719ac4c77c069a8b351e835)), closes [#457](https://github.com/VitruvianSoftware/vitruvian-core/issues/457)

## [1.0.3](https://github.com/VitruvianSoftware/mcp-slack/compare/v1.0.2...v1.0.3) (2026-05-07)


### Bug Fixes

* enforce strict stderr logging for MCP stdio transport ([ba4e893](https://github.com/VitruvianSoftware/mcp-slack/commit/ba4e893a9029a86ba91f4e6686d9cc107bc0195b))
* ignore .github directory in addlicense check ([cb0ffe8](https://github.com/VitruvianSoftware/mcp-slack/commit/cb0ffe87871e8da1a615df20c2fa8d600b331620))
