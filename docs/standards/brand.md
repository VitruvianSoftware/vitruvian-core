# Vitruvian brand standard

> **Status:** Active (cutover completed 2026-11-12).
> **Owner:** James. **Applies to:** every product, repo, doc and agent in `vitruvian-core`.

## 1. Naming rule

Every shipped product is **Vitruvian \<Noun\>** — one real English noun that says plainly
what the product does. One company name, one pattern, no camel-case compounds
(`HomeSpeaker`) and no invented words (`Tabula`).

- **Vitruvian Software** is the company. It appears in legal text, the site footer,
  signing identities and the `VitruvianSoftware` GitHub org. Products never put
  "by Vitruvian Software" in their name.
- **Vitruvian Atrium** is the macOS host app (notch island, Command Bar, Radial menu)
  that runs tools over JSON-RPC. Tools use `Vitruvian <Noun>` too (`Vitruvian Code`,
  `Vitruvian Speaker`, `Vitruvian Remote`, `Vitruvian GitHub`, `Vitruvian TV`).
- **Intentional multi-word display names:** `Vitruvian DevX CLI` keeps `DevX CLI` so it
  reads clearly as a developer CLI; MCP servers use `Vitruvian <Target> MCP` in prose and
  `vitruvian-<target>-mcp` in directory, binary and repo slugs; `Vitruvian TV` uses the
  standard acronym.
- **Internal tools and standalone utilities** get no `Vitruvian` product brand (`backstage`,
  `gods-eye-view`, `ostation`, `oauth-user-inspector`, `gh-watch`, `Daytona Platinum`,
  Antigravity plugins, Pulumi libraries and `tools/`).

Old product names are **retired, not aliased**. `tools/lint-naming` (`RET001`) fails CI if
a retired name reappears outside the allowlisted records and kept identifiers below.

## 2. Products and mirror repos

Verified against `apps/`, `packages/`, `catalog/` and `StandaloneRepo` in
`infrastructure/pulumi/platform/repo-config/internal/copybara_sync/sync.go`:

| Product | Former name | Monorepo folder | Bundle / tool / CLI ID | Release component | Mirror repo (`VitruvianSoftware/…`) |
|---|---|---|---|---|---|
| **Vitruvian Code** | Nexus Agent | `apps/desktop/vitruvian-code` | `com.vitruviansoftware.code`, `dev.vitruvian.code` | `vitruvian-code` | `vitruvian-code` |
| **Vitruvian Speaker** | HomeSpeaker | `apps/desktop/vitruvian-speaker` | `com.vitruviansoftware.speaker`, `dev.vitruvian.speaker` | `vitruvian-speaker` | `vitruvian-speaker` |
| **Vitruvian Courier** | Courier | `apps/desktop/vitruvian-courier` | `com.vitruviansoftware.courier` (kept) | `vitruvian-courier` | `vitruvian-courier` |
| **Vitruvian Atrium** | Vitruvian (host app) | `apps/desktop/vitruvian-atrium` | `com.vitruviansoftware.vitruvian` (kept) | `vitruvian-atrium` | `vitruvian-atrium` |
| **Vitruvian Remote** | *(already compliant)* | `apps/mobile/vitruvian-remote` | `dev.vitruvian.remote`, `com.vitruviansoftware.remote` | `vitruvian-remote` | `vitruvian-remote` |
| **Vitruvian Tabs** | Tabula | `apps/suites/vitruvian-tabs` | CLI `vitruvian-tabs` | `vitruvian-tabs-{api,cli,extension,shared,web}` | — *(monorepo-only)* |
| **Vitruvian Wand** | Wand | `apps/suites/vitruvian-wand` | `com.vitruviansoftware.wand`, CLI `vitruvian-wand` | `vitruvian-wand` | — *(monorepo-only)* |
| **Vitruvian Watch** | Wear OS app | `apps/mobile/vitruvian-watch` | `com.vitruviansoftware.watch.{pulse,remote,home,code}` | `vitruvian-watch` | — *(monorepo-only)* |
| **Vitruvian Relay** | Relay | `apps/suites/vitruvian-relay` | `vitruvian-relay-spike` *(spike)* | — *(pre-release)* | — *(monorepo-only)* |
| **Vitruvian DevX CLI** | `devx` | `apps/cli/vitruvian-devx` | CLI `devx` (kept) | `vitruvian-devx` | `vitruvian-devx` |
| **Vitruvian Homelab** | `homelab` | `apps/cli/vitruvian-homelab` | CLI `homelab` (kept) | `vitruvian-homelab` | `vitruvian-homelab` |
| **Vitruvian Deck** | ESP32-S3 desk companion | `apps/embedded/vitruvian-deck` | `vitruvian-deck.local` | `vitruvian-deck` | `vitruvian-deck` |
| **Vitruvian Roborock MCP** (`vitruvian-roborock-mcp`) | `mcp-roborock` | `apps/mcp/vitruvian-roborock-mcp` | MCP `vitruvian-roborock-mcp`, CLI `rrctl` (kept) | — *(none)* | `vitruvian-roborock-mcp` |
| **Vitruvian Slack MCP** (`vitruvian-slack-mcp`) | `mcp-slack` | `apps/mcp/vitruvian-slack-mcp` | MCP & CLI `vitruvian-slack-mcp` | `vitruvian-slack-mcp` | `vitruvian-slack-mcp` |
| **Vitruvian GitHub** | GitHub tool | `apps/extensions/atrium/vitruvian-github` | `dev.vitruvian.github` | `vitruvian-github` | `vitruvian-github` |
| **Vitruvian TV** | TV tool | `apps/extensions/atrium/vitruvian-tv` | `dev.vitruvian.tv` | `vitruvian-tv` | — *(monorepo-only)* |
| **Vitruvian Tool SDK** (`vitruvian-sdk`) | *(already compliant)* | `packages/vitruvian-sdk` | `VitruvianToolKit` | `vitruvian-sdk` | `vitruvian-sdk` |

Unbranded mirrors in `sync.go` stay as-is: `oauth-user-inspector`, `gh-watch`,
`site-vitruviansoftware-dev`, `pulumi-library`, `pulumi_go-example-foundation` and
`pulumi_ts-example-foundation`.

### Where things live

The path says what kind of thing it is, and the leaf keeps the brand.

| Path | Meaning |
|---|---|
| `apps/<platform>/vitruvian-<noun>` | A standalone app (`apps/desktop/vitruvian-atrium`, `apps/mobile/vitruvian-remote`). |
| `apps/<platform>/vitruvian-<noun>/atrium-extension/` | The same app also plugs into Atrium. The folder is always named `atrium-extension` and holds the extension's `vitruvian-tool.json` and its other files. It sits next to the code that builds it, so Code and Remote keep it one level down (`vitruvian-code/macos/atrium-extension/`, `vitruvian-remote/macmenu/atrium-extension/`). |
| `apps/extensions/atrium/vitruvian-<noun>` | A product that lives only inside Atrium (`vitruvian-github`, `vitruvian-tv`). |

`tools/conformance` (the `LAYOUT` group) fails when a `vitruvian-tool.json` sits anywhere else; the SDK's samples and conformance tools are exempt.

## 3. Kept on purpose

These identifiers stayed at their pre-cutover values because renaming them would break
stored user data, live cloud state, external credentials or daily shell muscle memory for
no visible benefit:

- **Stored user data, wire keys and bundle/keychain IDs:** Courier's internal Matrix server
  name `courier.local` (baked into every stored room, user and media ID), saved config keys
  (`courier_enabled`) and Remote wire-protocol keys; Courier's bundle ID and Keychain
  services (`com.vitruviansoftware.courier*`); Atrium's bundle ID
  `com.vitruviansoftware.vitruvian` (plus helper IDs `.fan-control` and `.now-playing`,
  `window.vitruvian` and `VITRUVIAN_*` env vars); Vitruvian Remote's Android `applicationId`
  `dev.vitruvian.remote`; Atrium's tool ID
  namespace `dev.vitruvian.*` (separate from app bundle IDs `com.vitruviansoftware.*`);
  Deck's NVS namespace and `"ESP32-S3"` when naming the hardware chip.
- **CLI commands and Homebrew tokens:** `devx`, `homelab` and `rrctl` stay short for
  interactive terminal use; `speaker-broadcast` and `~/.gemini/speaker_broadcast.json` stay
  stable for external agent hooks; Homebrew formulas stay `devx` and `homelab`, and the
  Vitruvian Code cask token in `homebrew-tap` stays `nexus-agent`.
- **Historical releases, catalog handovers and archives:** git history, `CHANGELOG.md`
  files, pre-cutover release tags (`courier-v*` through `0.3.17`, `home-speaker-v*` through
  `1.41.0`, `vitruvian-v3.89.0`, `esp32-s3-v0.1.12`), `replaces` entries in
  `catalog/tools.json` (`dev.vitruvian.nexus-agent`, `dev.vitruvian.homespeaker`) so
  existing Atrium installs swap cleanly, and dated planning/audit docs under
  `docs/archive/`, `docs/superpowers/` and `docs/standards/`.
- **Pulumi, cloud, Kubernetes and Copybara state:** all Pulumi stacks under
  `infrastructure/`; Vitruvian Tabs' live Pulumi projects (`tabula-*`), Cloud Run services,
  Artifact Registry, `TABULA_*` secrets, GitHub Environments and domains
  (`tabula*.vitruviansoftware.dev`, `tabula.{com,app,dev}`); Slack MCP's `mcp-slack*`
  Kubernetes namespace, Argo CD app, SealedSecrets and Zitadel stack; Copybara workflow
  keys, `LegacyRepo` redirect guards, `*_REV_ID` / `*_SYNC_SSH_KEY` / `*_DISPATCH_APP_*`
  secrets and `.github/workflows/copybara-export-*.yaml`; GitHub team slugs (`*-team`), the
  `"Vitruvian Desktop"` GitHub App (`docs/github-relay/`), Atrium's CI unit
  `vitruvian-desktop-macos` and site catalog keys (`vitruvianDesktopTools`), and Stripe
  donation keys (`/donate/<key>/`, `.github/FUNDING.yml`).

## 4. Cutover record

**Done 2026-11-12, hard cutover, no migrations.** PR #4631 renamed product folders, Bazel
targets, Swift/Rust/Go/TS packages and user-facing labels in one pass with no runtime data
migrations, Keychain copy shims or CLI aliases. PRs #4651 and #4661 renamed the standalone
mirror repositories in place under `VitruvianSoftware/vitruvian-*`, with GitHub serving
permanent URL and git redirects from the old repo names.

## 5. Naming a new product

Use this checklist from the first commit:

- [ ] **Pick the noun:** one plain English noun for what it does (`Vitruvian <Noun>`), with
      no clash against a known developer product in the same space.
- [ ] **Monorepo folder:** `apps/<kind>/vitruvian-<noun>` (or
      `apps/mcp/vitruvian-<noun>-mcp` for an MCP server).
- [ ] **Bundle and tool IDs:** `com.vitruviansoftware.<noun>` for macOS/Android apps
      (`Vitruvian<Noun>` for Swift modules/types, `~/Library/Application Support/Vitruvian <Noun>`
      on disk), and `dev.vitruvian.<noun>` if it ships an Atrium tool.
- [ ] **CLI and env vars:** command `vitruvian-<noun>`, env prefix `VITRUVIAN_<NOUN>_*`.
- [ ] **Mirror repo:** `VitruvianSoftware/vitruvian-<noun>` via `StandaloneRepo` in
      `infrastructure/pulumi/platform/repo-config/internal/copybara_sync/sync.go` (omit if
      monorepo-only).
- [ ] **Release component:** `vitruvian-<noun>` in `release-please-config.json` (tags
      `vitruvian-<noun>-v*`).
