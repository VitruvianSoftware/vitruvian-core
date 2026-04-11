# Changelog

## [1.10.1](https://github.com/VitruvianSoftware/nexus-agent/compare/nexus-agent-v1.10.0...nexus-agent-v1.10.1) (2026-04-11)


### Bug Fixes

* correct session resumption to use specific UUID ([4c10ca3](https://github.com/VitruvianSoftware/nexus-agent/commit/4c10ca33f24dd8d2e24af12437564d494132d8ce))

## [1.10.0](https://github.com/VitruvianSoftware/nexus-agent/compare/nexus-agent-v1.9.0...nexus-agent-v1.10.0) (2026-04-11)


### Features

* add editable model badge to chat header and pass custom model to CLI invocations ([ceadc87](https://github.com/VitruvianSoftware/nexus-agent/commit/ceadc87eb8e9e9466aa76af90e39e28712d87936))
* add plan mode to restrict agent to read-only explanations with UI toggle and system prompt enforcement ([a087eda](https://github.com/VitruvianSoftware/nexus-agent/commit/a087eda4c290f05c103770681400d40d86f7b066))
* add retry functionality for failed CLI prompts in QuickPromptWindow ([984f4e5](https://github.com/VitruvianSoftware/nexus-agent/commit/984f4e58f15870b204823c70db65ba7fd7c4a814))
* add working directory selection UI and status badge to QuickPromptWindow ([4ea7cc9](https://github.com/VitruvianSoftware/nexus-agent/commit/4ea7cc969bd79f6c55dff91783088a716323a888))
* add worktree mode toggle and git repository detection to QuickPromptWindow ([d480978](https://github.com/VitruvianSoftware/nexus-agent/commit/d4809783bf5452cf33d6253a7fb15e6f81d5b927))
* track and display LLM usage statistics, model names, and stop reasons in message history ([528e9f8](https://github.com/VitruvianSoftware/nexus-agent/commit/528e9f8e571e18a38def3d268e0e2cb963fadb5f))
* update Gemini output format, improve streaming message parsing, and refactor Ollama model discovery to be asynchronous ([0fec09e](https://github.com/VitruvianSoftware/nexus-agent/commit/0fec09e470c087d658707d53d4eaa44b21c685f9))

## [1.9.0](https://github.com/VitruvianSoftware/nexus-agent/compare/nexus-agent-v1.8.0...nexus-agent-v1.9.0) (2026-04-11)


### Features

* add ⌘N shortcut, update scroll button label, replace avatar with initials, and add line numbers to code blocks ([6c3faac](https://github.com/VitruvianSoftware/nexus-agent/commit/6c3faac050f8bfa5e434f4e411abdaaba9f308f4))
* add Claude Code provider support with stream-json integration and unified command execution logic ([583610e](https://github.com/VitruvianSoftware/nexus-agent/commit/583610ef5810c3b7dfbab246584ec19aae6a7ab9))
* add message count to session list and implement clear button for prompt input ([ef16d9e](https://github.com/VitruvianSoftware/nexus-agent/commit/ef16d9e7f0c1be863161a949af0251deeaff12b0))
* add opacity transition to session list and improve stop button hover states and styling ([265b07e](https://github.com/VitruvianSoftware/nexus-agent/commit/265b07e314f5f2eabd79d51b871ea6f6fbcc6c85))
* add resumed session indicator and generation elapsed time counter to QuickPromptWindow ([1065b00](https://github.com/VitruvianSoftware/nexus-agent/commit/1065b00821e7f932802821d67ab42c8594db5d9e))
* add separator to prompt header and update Esc key behavior to stop generation before dismissing ([849bc30](https://github.com/VitruvianSoftware/nexus-agent/commit/849bc30e39e2327e806974c88f48154d67d4b649))
* add session context menu, message count badge, and updated UI animations to QuickPromptWindow ([5e1f69f](https://github.com/VitruvianSoftware/nexus-agent/commit/5e1f69fe2c105b9fc3199a0c12317579e9901439))
* add session count badge to chat header and refactor stop button into reusable view component ([b839f07](https://github.com/VitruvianSoftware/nexus-agent/commit/b839f07555dd2b31cb0db9d0ccbf1586be515086))
* add session deep-linking to background notifications and update UI animation state ([aaa8840](https://github.com/VitruvianSoftware/nexus-agent/commit/aaa884083332cde143bc074657d05d0339818fe2))
* update timestamp formatting, add character count to prompt input, and enable copy button for all message types ([a933ed1](https://github.com/VitruvianSoftware/nexus-agent/commit/a933ed112bdb53a207b7c20fc2e9e79b43871941))

## [1.8.0](https://github.com/VitruvianSoftware/nexus-agent/compare/nexus-agent-v1.7.0...nexus-agent-v1.8.0) (2026-04-10)


### Features

* add confirmation step for clearing sessions and implement real-time streaming updates for assistant messages ([d9749e9](https://github.com/VitruvianSoftware/nexus-agent/commit/d9749e9a75094c9642f89d186587523ca589456c))
* add contextual command hints and modular, animated action buttons to QuickPromptWindow ([41ad625](https://github.com/VitruvianSoftware/nexus-agent/commit/41ad6254c145cf83052fc45a4f68efa482848ff1))
* add interactive chat provider switcher and improve input field focus styling ([e54cc88](https://github.com/VitruvianSoftware/nexus-agent/commit/e54cc887f7df6cd011882604d03932e2933511dd))
* add SendButtonView, implement error auto-dismissal, and enhance code block copy feedback ([d025e8f](https://github.com/VitruvianSoftware/nexus-agent/commit/d025e8f88a29f52a0ae48e0ed8cb400244a164b3))
* add session deletion support and improve session identification logic in QuickPromptWindow ([035a357](https://github.com/VitruvianSoftware/nexus-agent/commit/035a357fcb3509c6018714b3491d0c936fce9e30))
* add system notifications for background generation completion and improve UI transitions ([972f164](https://github.com/VitruvianSoftware/nexus-agent/commit/972f164db910e4decc53691f9da25f7b6f43ebf9))
* add window shadow updates during resize and improve UI animations for streaming status and input state ([c63caed](https://github.com/VitruvianSoftware/nexus-agent/commit/c63caedd5961c5f2dbf1473ecfba7c83239c61bd))
* improve QuickPromptWindow UI with crossfade transitions, interactive header buttons, and refined input animations. ([eba8ab6](https://github.com/VitruvianSoftware/nexus-agent/commit/eba8ab6a5118fabebccdabd4d5b431bb81183f65))
* improve QuickPromptWindow UI with message animations, refined styling, and scoped keyboard navigation ([8a2f55f](https://github.com/VitruvianSoftware/nexus-agent/commit/8a2f55f58b2a708f70815336c29a3cd6f84d756c))
* pass session title to chat view and improve scroll position tracking for auto-scrolling ([9cd8c32](https://github.com/VitruvianSoftware/nexus-agent/commit/9cd8c3208eccd0908320d0845347adb08db2361b))
* synchronize window pin state, animate message clearing, update sparkles styling, and persist prompt history ([b2657d9](https://github.com/VitruvianSoftware/nexus-agent/commit/b2657d9103caf7852d53358a1cc325bbb56e5436))

## [1.7.0](https://github.com/VitruvianSoftware/nexus-agent/compare/nexus-agent-v1.6.0...nexus-agent-v1.7.0) (2026-04-08)


### Features

* add session list switcher to active chat window header ([296dd98](https://github.com/VitruvianSoftware/nexus-agent/commit/296dd985bf34065499574fb2c25e54cabcbbcca0))


### Bug Fixes

* translate GitHub rate limit and 404 HTTP errors to human readable messages ([b4269db](https://github.com/VitruvianSoftware/nexus-agent/commit/b4269dbd9955be8077cecc3ec469ec64be932401))

## [1.6.0](https://github.com/VitruvianSoftware/nexus-agent/compare/nexus-agent-v1.5.2...nexus-agent-v1.6.0) (2026-04-08)


### Features

* standardise directory layout to ~/.config/nexus-agent ([503c782](https://github.com/VitruvianSoftware/nexus-agent/commit/503c7827d970ce6a68065d050b0932ce7528797d))

## [1.5.2](https://github.com/VitruvianSoftware/nexus-agent/compare/nexus-agent-v1.5.1...nexus-agent-v1.5.2) (2026-04-08)


### Bug Fixes

* resolve bot path resolution issues ([93f45c8](https://github.com/VitruvianSoftware/nexus-agent/commit/93f45c84159ef6ad179bfac1a1f2ea0b1f34fe33))

## [1.5.1](https://github.com/VitruvianSoftware/nexus-agent/compare/nexus-agent-v1.5.0...nexus-agent-v1.5.1) (2026-04-08)


### Bug Fixes

* **ui:** update missed UI text and window titles ([96cf7d7](https://github.com/VitruvianSoftware/nexus-agent/commit/96cf7d7981ce392d5324a78b759f73142f314b25))

## [1.5.0](https://github.com/VitruvianSoftware/nexus-agent/compare/nexus-agent-v1.4.3...nexus-agent-v1.5.0) (2026-04-08)


### Features

* add CI/CD pipeline with release-please, DMG packaging, and auto-updater ([286f0f2](https://github.com/VitruvianSoftware/nexus-agent/commit/286f0f2249df6bdb5de4fb155ca20ee8e2ee4111))
* add custom AI provider support to settings and update CLI configuration schema ([c45784a](https://github.com/VitruvianSoftware/nexus-agent/commit/c45784aa9ecb318063cb65cb5c1e9d458ea01388))
* add pin functionality to QuickPromptWindow to prevent auto-dismissal on click-outside ([46a4757](https://github.com/VitruvianSoftware/nexus-agent/commit/46a4757650d955f7d43bcba68e2b38fd35144bc0))
* complete rename and rebranding to NexusAgent ([ae1d980](https://github.com/VitruvianSoftware/nexus-agent/commit/ae1d980f9b08d834b6c2470dee2633ef0bbac536))
* **macos:** add About tab with app info, repo links, and in-place update ([ca84735](https://github.com/VitruvianSoftware/nexus-agent/commit/ca84735f8d25c10b671b7f4bc09b0e24b8793192))
* **macos:** add provider quick-picker to Quick Prompt input bar ([5692587](https://github.com/VitruvianSoftware/nexus-agent/commit/5692587f5bb73fe89717d40e7fff6726cee1d2a9))
* **macos:** implement 16 quick prompt UI/UX improvements ([41673fe](https://github.com/VitruvianSoftware/nexus-agent/commit/41673fe830d500d34997170a106ec2bc622b0108))
* **macos:** implement custom spring-physics and tahoe-style window animations ([98b91bc](https://github.com/VitruvianSoftware/nexus-agent/commit/98b91bc60708ea14dbf0e720b7685bab2c047130))
* **macos:** improve bot directory discovery and refactor quick prompt UI ([cea7d85](https://github.com/VitruvianSoftware/nexus-agent/commit/cea7d8587ff44893e816ef70bb920d229fc12de7))
* refactor settings view into a tabbed interface for better organization ([551daeb](https://github.com/VitruvianSoftware/nexus-agent/commit/551daeb2d740b2ac82fabb225d1c620beee81fe0))


### Bug Fixes

* **macos:** add ad-hoc signing to bundle and document quarantine removal for gatekeeper ([d7bc248](https://github.com/VitruvianSoftware/nexus-agent/commit/d7bc248a6a01e2f0827bc9518913a817af1aa83e))
* **macos:** proper auto-scroll anchoring during streams ([6ce8555](https://github.com/VitruvianSoftware/nexus-agent/commit/6ce85556535aab441d935e42582c774ddf3e7912))
* **macos:** remove ghost rectangle border from quick prompt panel ([d515949](https://github.com/VitruvianSoftware/nexus-agent/commit/d515949537425a8dbc06518129764612098002a7))
* **macos:** retry asset fetch if CI is still uploading ([7c0e01b](https://github.com/VitruvianSoftware/nexus-agent/commit/7c0e01b1df50836ff3aaf24f2428248375ee1146))
* **macos:** update checker parsing and error surfacing ([62b031c](https://github.com/VitruvianSoftware/nexus-agent/commit/62b031cefd37352f01c77307e479205488a613e9))
* **telegram:** neatly parse and filter upstream CLI errors ([c42f953](https://github.com/VitruvianSoftware/nexus-agent/commit/c42f953f7abbc3d6cf0668310de93ecac90c1629))

## [1.4.3](https://github.com/BlueCentre/nexus-agent/compare/nexus-agent-v1.4.2...nexus-agent-v1.4.3) (2026-04-08)


### Bug Fixes

* **telegram:** neatly parse and filter upstream CLI errors ([c42f953](https://github.com/BlueCentre/nexus-agent/commit/c42f953f7abbc3d6cf0668310de93ecac90c1629))

## [1.4.2](https://github.com/BlueCentre/nexus-agent/compare/nexus-agent-v1.4.1...nexus-agent-v1.4.2) (2026-04-08)


### Bug Fixes

* **macos:** proper auto-scroll anchoring during streams ([6ce8555](https://github.com/BlueCentre/nexus-agent/commit/6ce85556535aab441d935e42582c774ddf3e7912))
* **macos:** retry asset fetch if CI is still uploading ([7c0e01b](https://github.com/BlueCentre/nexus-agent/commit/7c0e01b1df50836ff3aaf24f2428248375ee1146))

## [1.4.1](https://github.com/BlueCentre/nexus-agent/compare/nexus-agent-v1.4.0...nexus-agent-v1.4.1) (2026-04-08)


### Bug Fixes

* **macos:** update checker parsing and error surfacing ([62b031c](https://github.com/BlueCentre/nexus-agent/commit/62b031cefd37352f01c77307e479205488a613e9))

## [1.4.0](https://github.com/BlueCentre/nexus-agent/compare/nexus-agent-v1.3.0...nexus-agent-v1.4.0) (2026-04-08)


### Features

* **macos:** add provider quick-picker to Quick Prompt input bar ([5692587](https://github.com/BlueCentre/nexus-agent/commit/5692587f5bb73fe89717d40e7fff6726cee1d2a9))

## [1.3.0](https://github.com/BlueCentre/nexus-agent/compare/nexus-agent-v1.2.0...nexus-agent-v1.3.0) (2026-04-08)


### Features

* **macos:** add About tab with app info, repo links, and in-place update ([ca84735](https://github.com/BlueCentre/nexus-agent/commit/ca84735f8d25c10b671b7f4bc09b0e24b8793192))

## [1.2.0](https://github.com/BlueCentre/nexus-agent/compare/nexus-agent-v1.1.1...nexus-agent-v1.2.0) (2026-04-08)


### Features

* **macos:** implement 16 quick prompt UI/UX improvements ([41673fe](https://github.com/BlueCentre/nexus-agent/commit/41673fe830d500d34997170a106ec2bc622b0108))

## [1.1.1](https://github.com/BlueCentre/nexus-agent/compare/nexus-agent-v1.1.0...nexus-agent-v1.1.1) (2026-04-08)


### Bug Fixes

* **macos:** add ad-hoc signing to bundle and document quarantine removal for gatekeeper ([d7bc248](https://github.com/BlueCentre/nexus-agent/commit/d7bc248a6a01e2f0827bc9518913a817af1aa83e))

## [1.1.0](https://github.com/BlueCentre/nexus-agent/compare/nexus-agent-v1.0.0...nexus-agent-v1.1.0) (2026-04-08)


### Features

* add CI/CD pipeline with release-please, DMG packaging, and auto-updater ([286f0f2](https://github.com/BlueCentre/nexus-agent/commit/286f0f2249df6bdb5de4fb155ca20ee8e2ee4111))
* add custom AI provider support to settings and update CLI configuration schema ([c45784a](https://github.com/BlueCentre/nexus-agent/commit/c45784aa9ecb318063cb65cb5c1e9d458ea01388))
* add pin functionality to QuickPromptWindow to prevent auto-dismissal on click-outside ([46a4757](https://github.com/BlueCentre/nexus-agent/commit/46a4757650d955f7d43bcba68e2b38fd35144bc0))
* **macos:** implement custom spring-physics and tahoe-style window animations ([98b91bc](https://github.com/BlueCentre/nexus-agent/commit/98b91bc60708ea14dbf0e720b7685bab2c047130))
* **macos:** improve bot directory discovery and refactor quick prompt UI ([cea7d85](https://github.com/BlueCentre/nexus-agent/commit/cea7d8587ff44893e816ef70bb920d229fc12de7))
* refactor settings view into a tabbed interface for better organization ([551daeb](https://github.com/BlueCentre/nexus-agent/commit/551daeb2d740b2ac82fabb225d1c620beee81fe0))


### Bug Fixes

* **macos:** remove ghost rectangle border from quick prompt panel ([d515949](https://github.com/BlueCentre/nexus-agent/commit/d515949537425a8dbc06518129764612098002a7))
