# Changelog

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
