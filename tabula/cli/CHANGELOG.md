# Changelog

## [0.1.10](https://github.com/VitruvianSoftware/vitruvian-core/compare/tabula-cli-v0.1.9...tabula-cli-v0.1.10) (2026-06-12)


### Features

* **tabula:** dev-channel self-update — dev-latest bundle, tabcli ext, update banner ([#45](https://github.com/VitruvianSoftware/vitruvian-core/issues/45) M1) ([#55](https://github.com/VitruvianSoftware/vitruvian-core/issues/55)) ([6fc8bf7](https://github.com/VitruvianSoftware/vitruvian-core/commit/6fc8bf7a4e5258386d9e88c7dd6290ad27f34cc2))

## [0.1.9](https://github.com/VitruvianSoftware/vitruvian-core/compare/tabula-cli-v0.1.8...tabula-cli-v0.1.9) (2026-06-12)


### Miscellaneous Chores

* **tabula-cli:** Synchronize tabula versions

## [0.1.8](https://github.com/VitruvianSoftware/vitruvian-core/compare/tabula-cli-v0.1.7...tabula-cli-v0.1.8) (2026-06-12)


### Miscellaneous Chores

* **tabula-cli:** Synchronize tabula versions

## [0.1.7](https://github.com/VitruvianSoftware/vitruvian-core/compare/tabula-cli-v0.1.6...tabula-cli-v0.1.7) (2026-06-11)


### Miscellaneous Chores

* **tabula-cli:** Synchronize tabula versions

## [0.1.6](https://github.com/VitruvianSoftware/vitruvian-core/compare/tabula-cli-v0.1.5...tabula-cli-v0.1.6) (2026-06-11)


### Miscellaneous Chores

* **tabula-cli:** Synchronize tabula versions

## [0.1.5](https://github.com/VitruvianSoftware/vitruvian-core/compare/tabula-cli-v0.1.4...tabula-cli-v0.1.5) (2026-06-11)


### Miscellaneous Chores

* **tabula-cli:** Synchronize tabula versions

## [0.1.4](https://github.com/VitruvianSoftware/vitruvian-core/compare/tabula-cli-v0.1.3...tabula-cli-v0.1.4) (2026-06-11)


### Features

* **tabula:** migrate Tabula into the monorepo as native Bazel packages ([#27](https://github.com/VitruvianSoftware/vitruvian-core/issues/27)) ([0e7557e](https://github.com/VitruvianSoftware/vitruvian-core/commit/0e7557e01d39ad9ceb30b6d211fa2fc0ffb2e34f))
* trigger release for cluster refactor ([1d877df](https://github.com/VitruvianSoftware/vitruvian-core/commit/1d877df795fc082eb3c5733a8318b50763f9a7d5))


### Bug Fixes

* correct session resumption to use specific UUID ([824de2d](https://github.com/VitruvianSoftware/vitruvian-core/commit/824de2dcab601d277d996af1b3f3a58691f40061))
* resolve bot path resolution issues ([942c9b4](https://github.com/VitruvianSoftware/vitruvian-core/commit/942c9b457fda4e0cfa7b166c416e6a8c3eff8761))
* trigger release for homebrew configuration ([240da7d](https://github.com/VitruvianSoftware/vitruvian-core/commit/240da7d7f8073f05bab6d3c4c1706dd68388b6e3))
* trigger release for homebrew configuration ([57fad83](https://github.com/VitruvianSoftware/vitruvian-core/commit/57fad8399f5d5367c9430c9a8ccbca6afcb36cef))
* trigger release for homebrew configuration ([b0ba158](https://github.com/VitruvianSoftware/vitruvian-core/commit/b0ba15813424e5f006b6d1bbb1fc32a7fe49cee3))

## [0.1.3](https://github.com/BlueCentre/tabula/compare/cli-v0.1.2...cli-v0.1.3) (2026-06-11)


### Features

* Add comprehensive web app testing infrastructure, enhance extension dashboard tests, and improve CLI coverage reporting. ([22dc53e](https://github.com/BlueCentre/tabula/commit/22dc53ec92d83e57a2577bf36badbbcc23b2f10a))
* Add detailed per-file coverage breakdown to `dev` command and CI PR comments. ([4f31b67](https://github.com/BlueCentre/tabula/commit/4f31b6744e52be0424d3d25ba0fd98aebdae8901))
* Add WorkOS Client ID loading from secrets and enhance WorkOS integration documentation with `tabcli` usage. ([01afefe](https://github.com/BlueCentre/tabula/commit/01afefe7817919453267d299375ccb1ddc47a18d))
* Add WorkOS client ID secret management and a Terraform import CLI command, while removing unused database module parameters ([055e6a4](https://github.com/BlueCentre/tabula/commit/055e6a49ffead0d2d12b0cbd9aa32faba5ba3782))
* **api:** Implement WorkOS authentication with JWTs in the API, update auth middleware, and enhance dev CLI to start the API backend. ([e2d90e7](https://github.com/BlueCentre/tabula/commit/e2d90e7cfe80bba6053c044c3dcd1f6118fc3721))
* **api:** Introduce SpaceGroup management and enhance workspace synchronization with nested items. ([6ad5a3f](https://github.com/BlueCentre/tabula/commit/6ad5a3fe9315225e062f3087ae38899e31df7fe3))
* **cli:** add --web flag to dev start command ([6b037e2](https://github.com/BlueCentre/tabula/commit/6b037e2a96ee2733177c9bcfd74da6860dd45e9c))
* **cli:** Add `dev coverage` command to run tests with coverage and display a summary report for workspaces. ([07d7eb7](https://github.com/BlueCentre/tabula/commit/07d7eb7d3e13f30a966a1ae4872b26c07186fb56))
* **cli:** add dev e2e command to run Playwright tests ([b720e15](https://github.com/BlueCentre/tabula/commit/b720e15de90b8dd6847d2e5ab9363b5efb034a3e))
* **cli:** add npm install step to dev check command ([134c0b6](https://github.com/BlueCentre/tabula/commit/134c0b63a87b18053db8683da337c0013f60e360))
* **cli:** add sync-db-secrets and refresh-secrets commands ([6cfcb4b](https://github.com/BlueCentre/tabula/commit/6cfcb4b26b55e0841f7c756a6e38558d81f11dd5))
* **cli:** add workos sync-redirects command to display callback URLs for all environments ([d739414](https://github.com/BlueCentre/tabula/commit/d739414334ddfe83acee4d8e5511763087a028e1))
* Implement environment-aware extension builds and automate GitHub environment setup via CLI ([a9199af](https://github.com/BlueCentre/tabula/commit/a9199af63e9cc860080175a826cb4ee445480de6))
* **infra:** Automate Upstash Redis provisioning with a new Terraform module and integrate its secrets into the CLI and API. ([e82e902](https://github.com/BlueCentre/tabula/commit/e82e902514caece6cd29954ccb6254f29d09aeba))
* Introduce WorkOS CLI wrapper, centralize secret loading, and enable Redis TLS in dev infrastructure. ([76317b7](https://github.com/BlueCentre/tabula/commit/76317b776d8a191db245c5edf376ea5d82ff29a6))


### Bug Fixes

* **cli:** use printf instead of echo -n for POSIX-compliant secret handling ([9d7aca8](https://github.com/BlueCentre/tabula/commit/9d7aca8b044136b4de1df373f5fada5f960d6f5b))
* Implement sync API integration tests, add tab group support to workspace schemas, and introduce CLI coverage checks ([853abf2](https://github.com/BlueCentre/tabula/commit/853abf23a4c1c59dd1c08ed14ab25e1b07be36d4))
* Implement workspace isolation to manage active tabs independently across workspaces. ([45c016f](https://github.com/BlueCentre/tabula/commit/45c016f0b4c9ade0656aaae3197a5c9e2a65d83e))
* Improve the cli to show failed threshhold ([ccb13db](https://github.com/BlueCentre/tabula/commit/ccb13dbf2789295ab5f4c0fd90ff7cadd2e1046b))

## [0.1.2](https://github.com/BlueCentre/tabula/compare/cli-v0.1.1...cli-v0.1.2) (2025-12-22)


### Features

* MVP Workspace CRUD and Tab Management ([#18](https://github.com/BlueCentre/tabula/issues/18)) ([0cfa2f3](https://github.com/BlueCentre/tabula/commit/0cfa2f357482f8b806a886dd06654853cca03812))

## [0.1.1](https://github.com/BlueCentre/tabula/compare/cli-v0.1.0...cli-v0.1.1) (2025-12-22)


### Features

* add 'drift' command to detect infrastructure drift ([fb3c393](https://github.com/BlueCentre/tabula/commit/fb3c393dc4e486be5a66872736527065676feaa9))
* add 'rebuild' command to TabCLI for rebuilding the tool ([e8c953d](https://github.com/BlueCentre/tabula/commit/e8c953dd0e5a340584361f6a899eb0a4a7a24ab1))
* Add `db list` CLI command to display database records for a model and update Prisma to v6.19.1. ([05515a0](https://github.com/BlueCentre/tabula/commit/05515a01b8003bdb79953c9f336dfff04c0cf293))
* Add `infra list` and `destroy` commands, enhance `dev check` with interactive lint auto-fix, and improve `infra` command initialization and authentication with updated documentation. ([a9016ce](https://github.com/BlueCentre/tabula/commit/a9016ce43a9544b74c9191638905267a7305332f))
* add `infra sync` command to apply Terraform configurations and update secrets. ([316d67b](https://github.com/BlueCentre/tabula/commit/316d67bfa30ba3b0e809c097e70c53bf698c9301))
* Add authentication and verification commands for Neon integration ([8ef89e4](https://github.com/BlueCentre/tabula/commit/8ef89e4ab7162dd3b1dccd97f8811d0515fe7ece))
* Add gcloud authentication steps for CLI and Application Default Credentials ([5041e5d](https://github.com/BlueCentre/tabula/commit/5041e5d65b158ab71fbb6715c3552dea381855e0))
* Add GitHub command for managing repository secrets and status ([029164a](https://github.com/BlueCentre/tabula/commit/029164a99dcdaa040515e4fa3caf624e1eb412f0))
* Add Neon Organization ID handling and update API image reference in Terraform variables ([e4fdd8b](https://github.com/BlueCentre/tabula/commit/e4fdd8b70bc574ca1d27ac610fa7a6343868232e))
* Add setup command for GCP project with configuration and billing checks ([225f840](https://github.com/BlueCentre/tabula/commit/225f840cb5766a1fb14be7fb7e65f8c9304f5a9e))
* add TabCLI platform tool for operational workflows ([89f8274](https://github.com/BlueCentre/tabula/commit/89f8274e53e20c5b7a02123144559a3d7102f2db))
* enhance checkAndPromptInit function to support spinner management during initialization ([57fa422](https://github.com/BlueCentre/tabula/commit/57fa422ed0a9f6e7be6b14fcd663b350cf8bc4c5))
* Enhance configuration management by typing getConfig and saveConfig functions, and add .neon file for organization ID ([8cd9ef1](https://github.com/BlueCentre/tabula/commit/8cd9ef185f9631a1e9fbb84f6d80e1da1386311c))
* Enhance Neon authentication to sync API key with local config and store in Google Secret Manager ([66fb444](https://github.com/BlueCentre/tabula/commit/66fb444cd6ed677f245aac72d1ca23b8dce590f6))
* Implement secrets pulling from Google Secret Manager to local config ([d31d447](https://github.com/BlueCentre/tabula/commit/d31d4471917b2e51f1ffb98c071adb9f07307bab))
* Introduce infrastructure management commands and refactor deployment process ([2dfc674](https://github.com/BlueCentre/tabula/commit/2dfc6744cf581afb467473f0cfafbc89b64a134e))
* Load Neon API key before infrastructure initialization and reformat gcloud deploy command arguments. ([0b94237](https://github.com/BlueCentre/tabula/commit/0b942379475424ce411101e421225bc0ae6b6abf))
* Refactor project ID handling in infrastructure commands for improved configuration management ([d8c063b](https://github.com/BlueCentre/tabula/commit/d8c063bc9df63f6e313b6ab37fc14a9b48343108))
* Update authentication error handling and refactor infrastructure configuration for improved clarity and functionality ([bd969fd](https://github.com/BlueCentre/tabula/commit/bd969fd9b81b9ab0cdf1ff7d7c8a1724d0f97033))
* update local config with database URL from Terraform output and reformat gcloud deploy commands ([70a545c](https://github.com/BlueCentre/tabula/commit/70a545c2bbaae8cba6976cea15c2b6406665d2f6))
* update TabCLI commands for database management and local development setup ([df79760](https://github.com/BlueCentre/tabula/commit/df79760faa243a3b2d97ac022ac6f4f99c86fab2))


### Bug Fixes

* resolve CI pipeline failures ([89b5e49](https://github.com/BlueCentre/tabula/commit/89b5e49004fa77ec9da0b1d1075d43f19abc141e))
