# Changelog

## [0.1.10](https://github.com/VitruvianSoftware/vitruvian-core/compare/tabula-extension-v0.1.9...tabula-extension-v0.1.10) (2026-06-12)


### Features

* **tabula:** dev-channel self-update — dev-latest bundle, tabcli ext, update banner ([#45](https://github.com/VitruvianSoftware/vitruvian-core/issues/45) M1) ([#55](https://github.com/VitruvianSoftware/vitruvian-core/issues/55)) ([6fc8bf7](https://github.com/VitruvianSoftware/vitruvian-core/commit/6fc8bf7a4e5258386d9e88c7dd6290ad27f34cc2))

## [0.1.9](https://github.com/VitruvianSoftware/vitruvian-core/compare/tabula-extension-v0.1.8...tabula-extension-v0.1.9) (2026-06-12)


### Bug Fixes

* **tabula:** de-flake sync-journeys e2e ([#46](https://github.com/VitruvianSoftware/vitruvian-core/issues/46)) + drop 500ms tab-groups hack ([#47](https://github.com/VitruvianSoftware/vitruvian-core/issues/47)) ([#50](https://github.com/VitruvianSoftware/vitruvian-core/issues/50)) ([b0bf48a](https://github.com/VitruvianSoftware/vitruvian-core/commit/b0bf48a03d63f2af678798624bd311ceb6e0cec9))
* **tabula:** protect un-acked local edits in the pull-merge ([#51](https://github.com/VitruvianSoftware/vitruvian-core/issues/51)) ([#53](https://github.com/VitruvianSoftware/vitruvian-core/issues/53)) ([fb1789f](https://github.com/VitruvianSoftware/vitruvian-core/commit/fb1789f639f5a98e7bc08b8cc17fb3a2e30d84e0))

## [0.1.8](https://github.com/VitruvianSoftware/vitruvian-core/compare/tabula-extension-v0.1.7...tabula-extension-v0.1.8) (2026-06-12)


### Bug Fixes

* **tabula:** complete the signed-out dashboard UX and repair e2e ([#41](https://github.com/VitruvianSoftware/vitruvian-core/issues/41)) ([24af2b7](https://github.com/VitruvianSoftware/vitruvian-core/commit/24af2b76a453abc40bc2284692ba2258174a7dda))

## [0.1.7](https://github.com/VitruvianSoftware/vitruvian-core/compare/tabula-extension-v0.1.6...tabula-extension-v0.1.7) (2026-06-11)


### Bug Fixes

* **tabula:** dashboard signed-out state with a Sign in button ([#39](https://github.com/VitruvianSoftware/vitruvian-core/issues/39)) ([3e928f5](https://github.com/VitruvianSoftware/vitruvian-core/commit/3e928f5c0d9545a9fccc765ca2f8feb7851b09dd))

## [0.1.6](https://github.com/VitruvianSoftware/vitruvian-core/compare/tabula-extension-v0.1.5...tabula-extension-v0.1.6) (2026-06-11)


### Bug Fixes

* **tabula:** pin a stable extension ID via manifest key ([#37](https://github.com/VitruvianSoftware/vitruvian-core/issues/37)) ([e3619af](https://github.com/VitruvianSoftware/vitruvian-core/commit/e3619af4a225269d19551abd0b0a5ca308772a09))

## [0.1.5](https://github.com/VitruvianSoftware/vitruvian-core/compare/tabula-extension-v0.1.4...tabula-extension-v0.1.5) (2026-06-11)


### Miscellaneous Chores

* **tabula-extension:** Synchronize tabula versions

## [0.1.4](https://github.com/VitruvianSoftware/vitruvian-core/compare/tabula-extension-v0.1.3...tabula-extension-v0.1.4) (2026-06-11)


### Features

* **tabula:** migrate Tabula into the monorepo as native Bazel packages ([#27](https://github.com/VitruvianSoftware/vitruvian-core/issues/27)) ([0e7557e](https://github.com/VitruvianSoftware/vitruvian-core/commit/0e7557e01d39ad9ceb30b6d211fa2fc0ffb2e34f))
* **tabula:** version/deploy provenance for API and extension ([#32](https://github.com/VitruvianSoftware/vitruvian-core/issues/32)) ([ba8e289](https://github.com/VitruvianSoftware/vitruvian-core/commit/ba8e289f8a0da61d7cabbf3f305f113b63401c79))
* trigger release for cluster refactor ([1d877df](https://github.com/VitruvianSoftware/vitruvian-core/commit/1d877df795fc082eb3c5733a8318b50763f9a7d5))


### Bug Fixes

* correct session resumption to use specific UUID ([824de2d](https://github.com/VitruvianSoftware/vitruvian-core/commit/824de2dcab601d277d996af1b3f3a58691f40061))
* resolve bot path resolution issues ([942c9b4](https://github.com/VitruvianSoftware/vitruvian-core/commit/942c9b457fda4e0cfa7b166c416e6a8c3eff8761))
* trigger release for homebrew configuration ([240da7d](https://github.com/VitruvianSoftware/vitruvian-core/commit/240da7d7f8073f05bab6d3c4c1706dd68388b6e3))
* trigger release for homebrew configuration ([57fad83](https://github.com/VitruvianSoftware/vitruvian-core/commit/57fad8399f5d5367c9430c9a8ccbca6afcb36cef))
* trigger release for homebrew configuration ([b0ba158](https://github.com/VitruvianSoftware/vitruvian-core/commit/b0ba15813424e5f006b6d1bbb1fc32a7fe49cee3))

## [0.1.3](https://github.com/BlueCentre/tabula/compare/extension-v0.1.2...extension-v0.1.3) (2026-06-11)


### Features

* (Phase 2) Add search history, filters, and Next.js web dashboard ([#35](https://github.com/BlueCentre/tabula/issues/35)) ([1bc8ff1](https://github.com/BlueCentre/tabula/commit/1bc8ff16545e87ae35465fca930ba99c28f46e12))
* Add `GhostOverlay` for drag-and-drop feedback and implement locking in sync service for robustness ([2d8e449](https://github.com/BlueCentre/tabula/commit/2d8e449817104c0a8076e6ef12d60e02bb981f78))
* Add `useEffect` hook to initialize sync store on component mount. ([9f9fae2](https://github.com/BlueCentre/tabula/commit/9f9fae270c6401df7da2bb438aa6f01b4a84c71e))
* Add a centrally-positioned search bar to the dashboard header that triggers the command palette ([d0b2b51](https://github.com/BlueCentre/tabula/commit/d0b2b5172405c6cfe401f35bb599fa9c2e21d36a))
* Add account settings UI and user profile management endpoints ([#20](https://github.com/BlueCentre/tabula/issues/20)) ([29cb2d5](https://github.com/BlueCentre/tabula/commit/29cb2d5130cc547dd8c381e90e14e19cca406b79))
* add automatic workspace backup before switching and E2E tests for the backup UI ([580449d](https://github.com/BlueCentre/tabula/commit/580449db70d499b8d8d0603887af5d00bc1df237))
* Add backup management with new API endpoints and Account Settings UI. ([f37092f](https://github.com/BlueCentre/tabula/commit/f37092f2505c4c21c440ee20594424259bcff91d))
* Add comprehensive web app testing infrastructure, enhance extension dashboard tests, and improve CLI coverage reporting. ([22dc53e](https://github.com/BlueCentre/tabula/commit/22dc53ec92d83e57a2577bf36badbbcc23b2f10a))
* Add emoji auto-detection for workspace titles, introduce a new Tooltip component, and refactor MenuOverlay to use portals ([f6ee2ca](https://github.com/BlueCentre/tabula/commit/f6ee2ca6f6796197a12b28784421b60e88ef0a06))
* Add empty states for workspace list and space groups ([#27](https://github.com/BlueCentre/tabula/issues/27)) ([e19c261](https://github.com/BlueCentre/tabula/commit/e19c261e123bb156ba0873b9454f8169edbe6c7a))
* Add generic empty state component and integrate it with new illustrations for empty tabs and resources ([b2163a9](https://github.com/BlueCentre/tabula/commit/b2163a97d43a778ba90f2c505e10dfa24cbf5571))
* Add section action menu with "Open All", "Add Resource", and "Delete Section" options. ([b399977](https://github.com/BlueCentre/tabula/commit/b3999770d0cbc346e21c587249de98923b9a9a4c))
* add SpaceGroup model, implement a custom confirmation modal, and refine space group data synchronization and color handling. ([89ae4bc](https://github.com/BlueCentre/tabula/commit/89ae4bcfb03822e27a4f9e6701764303266d95be))
* Add theme switching functionality with dark mode support. ([cc495d5](https://github.com/BlueCentre/tabula/commit/cc495d54f80c497724459bc6a3ea896702deebc0))
* Add UI for managing space groups, including rename, color, and delete options. ([e6a48c5](https://github.com/BlueCentre/tabula/commit/e6a48c587b5b6396c0a1845b01b473029599dd3f))
* Add visual grouping for tabs in the dashboard and preserve tab group membership when moving tabs ([8939c18](https://github.com/BlueCentre/tabula/commit/8939c180111875a92bea8ae91f87de9ec27d1c4d))
* **api:** Introduce SpaceGroup management and enhance workspace synchronization with nested items. ([6ad5a3f](https://github.com/BlueCentre/tabula/commit/6ad5a3fe9315225e062f3087ae38899e31df7fe3))
* **dashboard:** show extension version in sidebar footer ([1b75c47](https://github.com/BlueCentre/tabula/commit/1b75c476380d1c5060f9fa57d84d3f102ad91632))
* enable inline section renaming in dashboard and add sections property to Workspace type ([3807945](https://github.com/BlueCentre/tabula/commit/38079457d7c9cbc394fe35ee5deb8f103da3fcb2))
* **extension:** add URL-based routing for workspace switching ([ad480a5](https://github.com/BlueCentre/tabula/commit/ad480a569f97bf6f86df7b9594e66a8100c9daec))
* implement API synchronization for workspace and space group data ([99ebb45](https://github.com/BlueCentre/tabula/commit/99ebb45558b9c57ce5441147859c40c4171c7cc6))
* implement dedicated modal for section creation and update modal styling to use CSS variables. ([e9c1976](https://github.com/BlueCentre/tabula/commit/e9c197616c3020d15d4f5924644768ddd6fbc90c))
* Implement drag-and-drop reordering for workspaces in the sidebar. ([f954a44](https://github.com/BlueCentre/tabula/commit/f954a44d7829c9d38b57b7e3b0a925adec93d0ba))
* Implement dynamic accent colors for active workspace menu items, prioritizing workspace or group color, and adjust active state background ([72a4cd7](https://github.com/BlueCentre/tabula/commit/72a4cd7472514531660ee7f9be25977906b7a46f))
* Implement environment-aware extension builds and automate GitHub environment setup via CLI ([a9199af](https://github.com/BlueCentre/tabula/commit/a9199af63e9cc860080175a826cb4ee445480de6))
* Implement Global Search (Cmd+K) with CommandPalette component ([#25](https://github.com/BlueCentre/tabula/issues/25)) ([25a1bc8](https://github.com/BlueCentre/tabula/commit/25a1bc80caf9f48137215763991ece54142a5527))
* Implement inline editing for workspace names, replacing the dedicated rename button and modal. ([c76ff41](https://github.com/BlueCentre/tabula/commit/c76ff4166deaca9eb2d643205a21feeeb71af22c))
* Implement NoteEditor with markdown parsing, preview, toolbar, and popout, integrating it into NotesPanel ([29b141c](https://github.com/BlueCentre/tabula/commit/29b141c93cca29785d674d5c4ad832fc8d848e62))
* implement popup-based authentication, remove direct email/password login/signup, and update auth service, UI, and tests. ([d6ab3ee](https://github.com/BlueCentre/tabula/commit/d6ab3eec83da43638b5b336a82743d1aad8cd625))
* Implement Server-Sent Events (SSE) for real-time sync notifications and client subscriptions. ([f577a83](https://github.com/BlueCentre/tabula/commit/f577a83879890660bfe4da3db34eadc5f652ecac))
* Implement space group functionality for organizing workspaces, including storage, service methods, store actions, and UI integration. ([8aad8d1](https://github.com/BlueCentre/tabula/commit/8aad8d12841d80cf31115dfeb365f234c3857e90))
* Implement stable UUIDs for tab and tab group IDs, separating them from Chrome's ephemeral group IDs ([44cf403](https://github.com/BlueCentre/tabula/commit/44cf40393de248b4ceb29118a15e7af09b2ebfee))
* Implement Workona-style dashboard UI with new sections, notes, and tasks features, including modal support and refined tab management. ([42e494c](https://github.com/BlueCentre/tabula/commit/42e494c507f42398d87f5de42b5de4dda8c90823))
* Implement workspace context menu with rename, color, and move to section actions. ([61ad332](https://github.com/BlueCentre/tabula/commit/61ad332cbeecabdcd919b682535517da7b38443f))
* Improve dashboard layout stability for long content with `minmax(0, 1fr)` and `min-width: 0`, and add an E2E test to verify it. ([eb9123a](https://github.com/BlueCentre/tabula/commit/eb9123ab7a72074bfe0bf9a96d012d0b52dd2bbd))
* improve test coverage for Dashboard and WorkspaceService ([33b0ff7](https://github.com/BlueCentre/tabula/commit/33b0ff797f9e435460303fdf3adb8fc48bdce9be))
* improve test coverage for entry points ([959865f](https://github.com/BlueCentre/tabula/commit/959865fbe8ab52c9d96030bf0030dfe7023f8268))
* Introduce `useLatest` hook and documentation for stale closure prevention, and add E2E tests for tab synchronization. ([e89c291](https://github.com/BlueCentre/tabula/commit/e89c2913d3af589f11b74877b0494d63c9b06e95))
* introduce asynchronous sync service and store for workspace and space group data, replacing direct API calls with queued operations and providing UI status. ([0e696d1](https://github.com/BlueCentre/tabula/commit/0e696d1de2da08655774023a7271458c3479657c))
* introduce Material Icons component and implement collapsible dashboard sections ([7141934](https://github.com/BlueCentre/tabula/commit/7141934a6aded3bd7346b71f1228626c5b8aced6))
* Introduce MenuOverlay component to close dropdowns on outside clicks and add corresponding Playwright tests. ([6dd7502](https://github.com/BlueCentre/tabula/commit/6dd7502a6f0d441f4646e99e8686d1455f6f643f))
* Introduce tab group functionality, enabling tabs to be saved with their group IDs and groups to be restored with their original properties. ([58d3aef](https://github.com/BlueCentre/tabula/commit/58d3aef0375d534256cd6ae524da3a1fbea5628b))
* Redesign popup header with a two-row layout and introduce a compact variant for AccountSettings within the popup. ([f527a02](https://github.com/BlueCentre/tabula/commit/f527a020ca0a41a18bf64ea2cdaaa3cee5171ad1))
* relocate 'Add Section' button to the bottom of the resource list, remove 'Add Resource' button, simplify active tabs header, and add padding to tab list header. ([d45208d](https://github.com/BlueCentre/tabula/commit/d45208d13ca20052a51f0e065c41db6c46da8a8b))
* relocate SyncStatusIndicator from dashboard header to footer ([cd74fa8](https://github.com/BlueCentre/tabula/commit/cd74fa8cea7105e65580955c349fd6f66e9e124f))
* Relocate theme selection UI to AccountSettings and pass theme management props. ([28cb856](https://github.com/BlueCentre/tabula/commit/28cb8567bdc894fb53a9f6af687b661d9cfccb60))
* simplify database schema by removing SpaceGroup, Section, Resource, Note, and Task models, and update related UI components, data queries, and CSS variables. ([beceecb](https://github.com/BlueCentre/tabula/commit/beceecb596162ca612972f8ff6e41cd3fe3dc938))


### Bug Fixes

* Add optional chaining for safer access to `active.data.current` and `over.data.current` in drag and drop handlers ([335623e](https://github.com/BlueCentre/tabula/commit/335623e273e6ca52172b1d6481ad024a5097b4ae))
* **auth:** use configurable API_URL instead of hardcoded localhost ([046f2ba](https://github.com/BlueCentre/tabula/commit/046f2baf610b11d95bda80255d260ee9d186664e))
* conditionally add new workspaces to store to prevent duplicates from race conditions ([48c6a98](https://github.com/BlueCentre/tabula/commit/48c6a98f2a84ba89ea5915384535acedf3e59363))
* Correctly clear space group color by passing null instead of undefined and add test coverage. ([439e850](https://github.com/BlueCentre/tabula/commit/439e85040385ed606c8be3e1b5e737367b626668))
* **dashboard:** ensure DroppableContainer renders id to DOM ([84f1de3](https://github.com/BlueCentre/tabula/commit/84f1de3df1f3375a113667a7b81d40e79f1da85a))
* **dashboard:** use margin-bottom on tab group chunks for robust spacing ([21d8ec4](https://github.com/BlueCentre/tabula/commit/21d8ec472d58865ac833f8d66d47d2e4e1bcfba6))
* Enable drag-and-drop to manage tab groups and ungroup tabs ([828034c](https://github.com/BlueCentre/tabula/commit/828034c189105625ad4e1a8ce4acc36907b1f0ee))
* Enhance workspace synchronization by implementing monotonic timestamps and refining conflict resolution logic, adding new tests. ([b4d0e55](https://github.com/BlueCentre/tabula/commit/b4d0e55bec801929b14966f0d1e2069044e85090))
* Ensure backups are loaded only once per tab visit in account settings. ([bade0b0](https://github.com/BlueCentre/tabula/commit/bade0b0c45278d2abcccebac3336ac8543b67394))
* **extension:** tab groups lost on soft refresh ([6de9579](https://github.com/BlueCentre/tabula/commit/6de9579c82c9bd134c83f7e0a6f787643358b908))
* Filter pinned tabs from active tab lists. ([2370a31](https://github.com/BlueCentre/tabula/commit/2370a311f0852574ec8e2408febf6096a4523fe5))
* harden concurrency and fix production-readiness bugs (extension + API) ([#43](https://github.com/BlueCentre/tabula/issues/43)) ([c9dbaa0](https://github.com/BlueCentre/tabula/commit/c9dbaa064d848344a68eafd5ce7ac551abce79ac))
* Implement API sync for ungrouped workspaces and add test for move to group API sync. ([3441472](https://github.com/BlueCentre/tabula/commit/3441472b4ed8e34b773ae2944416bfa98eb5c716))
* Implement Last Write Wins for space group merging and explicitly sync null color values for API consistency. ([2e699f8](https://github.com/BlueCentre/tabula/commit/2e699f8c784ebe1206edf9e5c8b7cc761a18864d))
* Implement optimistic UI updates for workspace actions, add notes and tasks features, and enhance tab syncing and drag-and-drop behavior. ([1728ee9](https://github.com/BlueCentre/tabula/commit/1728ee9eb53d8dc9415f73fd7cbc77fa9c88e94a))
* Implement sync API integration tests, add tab group support to workspace schemas, and introduce CLI coverage checks ([853abf2](https://github.com/BlueCentre/tabula/commit/853abf23a4c1c59dd1c08ed14ab25e1b07be36d4))
* Implement workspace isolation to manage active tabs independently across workspaces. ([45c016f](https://github.com/BlueCentre/tabula/commit/45c016f0b4c9ade0656aaae3197a5c9e2a65d83e))
* improve real-time tab synchronization and UI updates in the dashboard by using an `activeWorkspaceRef` and optimizing tab handling. ([b2057db](https://github.com/BlueCentre/tabula/commit/b2057db6d9efa5322dd25c97d6b75fddd8921289))
* Improve workspace drag-and-drop stability by memoizing sorted workspaces and using dedicated store actions. ([0313928](https://github.com/BlueCentre/tabula/commit/031392832e17b7775303317dd3c91f0ed5797921))
* include orphaned workspaces in the ungrouped section and add a test for this behavior. ([d4b3b14](https://github.com/BlueCentre/tabula/commit/d4b3b1450cad7d89b6813a56f5eb6966f82bba27))
* Synchronize workspace moves with the API, add defensive data handling checks, and improve test stability. ([c1e976a](https://github.com/BlueCentre/tabula/commit/c1e976a98ef57b80750303cb32aa59dc15fcf505))
* **test:** move unit tests to src/hooks and update playwright config to avoid conflicts ([536a2e0](https://github.com/BlueCentre/tabula/commit/536a2e0aa8829876390bbca52481ad9c8211844d))
* Workspace menu move-to-section by awaiting async handler ([#33](https://github.com/BlueCentre/tabula/issues/33)) ([53bc2c7](https://github.com/BlueCentre/tabula/commit/53bc2c72b849cf353f54f23a7f539c89a9861636))

## [0.1.2](https://github.com/BlueCentre/tabula/compare/extension-v0.1.1...extension-v0.1.2) (2025-12-22)


### Features

* MVP Workspace CRUD and Tab Management ([#18](https://github.com/BlueCentre/tabula/issues/18)) ([0cfa2f3](https://github.com/BlueCentre/tabula/commit/0cfa2f357482f8b806a886dd06654853cca03812))

## [0.1.1](https://github.com/BlueCentre/tabula/compare/extension-v0.1.0...extension-v0.1.1) (2025-12-22)


### Features

* Implement MVP browser extension with workspace and tab management ([#15](https://github.com/BlueCentre/tabula/issues/15)) ([b2538ca](https://github.com/BlueCentre/tabula/commit/b2538ca2059bf14cb20f32c10267a5d4805fd562))
* set up complete development infrastructure with CI/CD, testing, and documentation ([49201d4](https://github.com/BlueCentre/tabula/commit/49201d4f7e00539f0d4f61d68e9758fb66a0945e))


### Bug Fixes

* exclude Playwright E2E tests from Jest test runner ([82c596a](https://github.com/BlueCentre/tabula/commit/82c596ab6707ef0cb2ba915502932c2003c07cfe))
* remove webServer config from Playwright to fix Extension E2E tests ([e39503f](https://github.com/BlueCentre/tabula/commit/e39503f070cfa6ef87e919101b90822d51ae8fcb))
* resolve CI pipeline failures ([89b5e49](https://github.com/BlueCentre/tabula/commit/89b5e49004fa77ec9da0b1d1075d43f19abc141e))
* resolve linting issues and complete development setup ([27a951e](https://github.com/BlueCentre/tabula/commit/27a951e82ac907c2b6566eb0f455d16b9a67712d))
* use npx for playwright in extension E2E tests ([48e44dc](https://github.com/BlueCentre/tabula/commit/48e44dc0203676f61b4b26a921874d3ec12bcc9b))
* use Playwright test API instead of Jest syntax in E2E tests ([83337c1](https://github.com/BlueCentre/tabula/commit/83337c19df5c175c44c8b003aa7839e422107802))
