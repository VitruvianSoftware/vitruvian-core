# Changelog

## [0.3.15](https://github.com/VitruvianSoftware/vitruvian-core/compare/courier-v0.3.14...courier-v0.3.15) (2026-11-10)


### Features

* **courier:** bring your own AI — local models found automatically, or your own cloud key ([#4482](https://github.com/VitruvianSoftware/vitruvian-core/issues/4482)) ([8f871f2](https://github.com/VitruvianSoftware/vitruvian-core/commit/8f871f24aaaebdaacbd8630e74495221a28301ba))

## [0.3.14](https://github.com/VitruvianSoftware/vitruvian-core/compare/courier-v0.3.13...courier-v0.3.14) (2026-11-10)


### Features

* **courier:** calmer look — one accent, simpler message box, less clutter ([#4476](https://github.com/VitruvianSoftware/vitruvian-core/issues/4476)) ([2b19316](https://github.com/VitruvianSoftware/vitruvian-core/commit/2b193165b2552ddfcc93de705e85766517d0629a))

## [0.3.13](https://github.com/VitruvianSoftware/vitruvian-core/compare/courier-v0.3.12...courier-v0.3.13) (2026-11-07)


### Features

* **courier:** the test copy opens with made-up chats (run_test_copy --seed) ([#4392](https://github.com/VitruvianSoftware/vitruvian-core/issues/4392)) ([00e10d7](https://github.com/VitruvianSoftware/vitruvian-core/commit/00e10d7eecec5f317cfdd6cbf09781bea5fb3d49))

## [0.3.12](https://github.com/VitruvianSoftware/vitruvian-core/compare/courier-v0.3.11...courier-v0.3.12) (2026-11-06)


### Features

* **courier:** put every column's header on one line ([#4380](https://github.com/VitruvianSoftware/vitruvian-core/issues/4380)) ([7bdf47e](https://github.com/VitruvianSoftware/vitruvian-core/commit/7bdf47e84d9991ea752d1bc442f1949d5f75523e))

## [0.3.11](https://github.com/VitruvianSoftware/vitruvian-core/compare/courier-v0.3.10...courier-v0.3.11) (2026-11-06)


### Features

* **courier:** show message actions on click and float Liquid Glass controls like macOS apps ([#4359](https://github.com/VitruvianSoftware/vitruvian-core/issues/4359)) ([1f6b6ac](https://github.com/VitruvianSoftware/vitruvian-core/commit/1f6b6ac82a29a9b01b5bbca7cc64b318e24425f6))

## [0.3.10](https://github.com/VitruvianSoftware/vitruvian-core/compare/courier-v0.3.9...courier-v0.3.10) (2026-11-05)


### Features

* **courier:** show who reacted, keep the hover bar next to the message, and polish reactions ([#4352](https://github.com/VitruvianSoftware/vitruvian-core/issues/4352)) ([86af745](https://github.com/VitruvianSoftware/vitruvian-core/commit/86af74542459dc58bdb5c40b189d417418d652b6))


### Bug Fixes

* **courier:** sync full channel rosters and resolve self profile and service bots in Chat Info ([#4351](https://github.com/VitruvianSoftware/vitruvian-core/issues/4351)) ([bb914ce](https://github.com/VitruvianSoftware/vitruvian-core/commit/bb914cee3f1f87384f90a78b97e49b6323761022))

## [0.3.9](https://github.com/VitruvianSoftware/vitruvian-core/compare/courier-v0.3.8...courier-v0.3.9) (2026-11-05)


### Bug Fixes

* **courier:** support pasting clipboard images into the message composer ([#4339](https://github.com/VitruvianSoftware/vitruvian-core/issues/4339)) ([120a885](https://github.com/VitruvianSoftware/vitruvian-core/commit/120a8851d796af791273efcb01176d9b3a1caa95))


### Performance Improvements

* **courier:** isolate timeline redraws on keystrokes, cache formatters and previews, and polish UI alignments ([#4340](https://github.com/VitruvianSoftware/vitruvian-core/issues/4340)) ([fc53d40](https://github.com/VitruvianSoftware/vitruvian-core/commit/fc53d40836cb91155e325000aac5dc2383a85779))

## [0.3.8](https://github.com/VitruvianSoftware/vitruvian-core/compare/courier-v0.3.7...courier-v0.3.8) (2026-11-05)


### Features

* **courier:** add native on-device macOS iMessage bridge ([#4337](https://github.com/VitruvianSoftware/vitruvian-core/issues/4337)) ([d2c5097](https://github.com/VitruvianSoftware/vitruvian-core/commit/d2c5097ab169066165261632ac71da4e17539d48))

## [0.3.7](https://github.com/VitruvianSoftware/vitruvian-core/compare/courier-v0.3.6...courier-v0.3.7) (2026-11-05)


### Performance Improvements

* **courier:** eliminate store N+1 queries, WAL fsync overhead, and redundant SwiftUI redraws ([#4333](https://github.com/VitruvianSoftware/vitruvian-core/issues/4333)) ([f836e60](https://github.com/VitruvianSoftware/vitruvian-core/commit/f836e6051b741c5062026fa3f0108ebbfee32b7c))

## [0.3.6](https://github.com/VitruvianSoftware/vitruvian-core/compare/courier-v0.3.5...courier-v0.3.6) (2026-11-04)


### Bug Fixes

* **courier:** avoid main-actor modal run-loop deadlock when quitting for update ([#4325](https://github.com/VitruvianSoftware/vitruvian-core/issues/4325)) ([9d81119](https://github.com/VitruvianSoftware/vitruvian-core/commit/9d8111956bc832de7aabaf0b7d179b018a7d8c60))

## [0.3.5](https://github.com/VitruvianSoftware/vitruvian-core/compare/courier-v0.3.4...courier-v0.3.5) (2026-11-04)


### Features

* **courier:** per-thread unread state, banner, thread notifications, and inbox preview ([#4323](https://github.com/VitruvianSoftware/vitruvian-core/issues/4323)) ([d66aae1](https://github.com/VitruvianSoftware/vitruvian-core/commit/d66aae1034b9fb041703bee67cc0ac8c60e16e19))


### Bug Fixes

* **courier:** backfill Google Chat thread replies with list_messages per topic ([#4321](https://github.com/VitruvianSoftware/vitruvian-core/issues/4321)) ([fcd9a54](https://github.com/VitruvianSoftware/vitruvian-core/commit/fcd9a5486d0075bfd12ff94bcfbd1b89689af717))

## [0.3.4](https://github.com/VitruvianSoftware/vitruvian-core/compare/courier-v0.3.3...courier-v0.3.4) (2026-11-04)


### Bug Fixes

* **courier:** Google Chat connects: the handshake stops waiting on an ack Google keeps open ([#4319](https://github.com/VitruvianSoftware/vitruvian-core/issues/4319)) ([654a310](https://github.com/VitruvianSoftware/vitruvian-core/commit/654a3100ad31d7fe15b9e25b2da7f820f8d27d58))

## [0.3.3](https://github.com/VitruvianSoftware/vitruvian-core/compare/courier-v0.3.2...courier-v0.3.3) (2026-11-03)


### Bug Fixes

* **courier:** make Google Chat reconnect failures readable and stop hot retry loops ([#4312](https://github.com/VitruvianSoftware/vitruvian-core/issues/4312)) ([d668d9d](https://github.com/VitruvianSoftware/vitruvian-core/commit/d668d9db9e8e087cb36831dbd393acb1b4d0351b))

## [0.3.2](https://github.com/VitruvianSoftware/vitruvian-core/compare/courier-v0.3.1...courier-v0.3.2) (2026-11-03)


### Bug Fixes

* **courier:** Settings opens again from every menu, and Hide Sidebar works ([#4269](https://github.com/VitruvianSoftware/vitruvian-core/issues/4269)) ([79e74b4](https://github.com/VitruvianSoftware/vitruvian-core/commit/79e74b4c0765a129db3931d6340b1141a9a15b2e))

## [0.3.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/courier-v0.3.0...courier-v0.3.1) (2026-11-02)


### Features

* **courier:** milestone 6: release through the desktop pipeline, and the cutover guide ([#4225](https://github.com/VitruvianSoftware/vitruvian-core/issues/4225)) ([3af18ea](https://github.com/VitruvianSoftware/vitruvian-core/commit/3af18eab51170edce21ba08b06d7394cb2896557))
* **courier:** serve GET /v1/accounts and /v1/messages/search for HomeSpeaker ([#4235](https://github.com/VitruvianSoftware/vitruvian-core/issues/4235)) ([501c79b](https://github.com/VitruvianSoftware/vitruvian-core/commit/501c79b5a604667b038dbdf44cbc67d3b862094a))
* **courier:** working menus, steady resizing, update checks and Liquid Glass ([#4238](https://github.com/VitruvianSoftware/vitruvian-core/issues/4238)) ([3cd7a05](https://github.com/VitruvianSoftware/vitruvian-core/commit/3cd7a050053acba9e23bdbc0373584497e07e0f6))

## Changelog
