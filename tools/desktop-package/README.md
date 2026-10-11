# Desktop Release Packaging Tool (`package-desktop`)

`//tools/desktop-package:package-desktop` is the canonical, reusable packaging tool for macOS desktop applications in `apps/desktop/` (`home-speaker`, `vitruvian`, `nexus-agent`, and future desktop apps).

It automates and enforces the standardized **6-point distribution contract** so developers and coding agents do not need to duplicate lipo thinning, codesigning, DMG packaging, checksumming, or cask maintenance by hand.

---

## The 6-Point Distribution Contract

Every desktop application released in `apps/desktop/` produces:

1. **Universal DMG** (`<App>-<version>-universal.dmg` and `<App>-<version>.dmg` compatibility alias)
2. **Apple Silicon DMG** (`<App>-<version>-arm64.dmg`) — Mach-O thinned to `arm64`
3. **Intel x86_64 DMG** (`<App>-<version>-x86_64.dmg`) — Mach-O thinned to `x86_64`
4. **Universal ZIP** (`<App>-<version>-universal.zip`) — Compressed `.app` bundle via `ditto`
5. **Homebrew Cask Formula** — `Casks/<app>.rb` in [VitruvianSoftware/homebrew-tap](https://github.com/VitruvianSoftware/homebrew-tap) via `HOMEBREW_TAP_TOKEN`
6. **Downloads Catalog Sync** — Registered in [apps/web/vitruviansoftware-dev/_data/downloads.yml](../../apps/web/vitruviansoftware-dev/_data/downloads.yml) via `//tools/sync-downloads`

Every `.dmg` and `.zip` artifact is accompanied by a SHA-256 sidecar file (`.sha256`).

---

## Usage

### Direct CLI / Bazel Run

```bash
# Package a pre-built .app bundle:
bazel run //tools/desktop-package:package-desktop -- \
  --app-path dist/HomeSpeaker.app \
  --version 1.11.0 \
  --dist-dir dist

# Package from a Bazel-built ZIP archive (e.g. from macos_application):
bazel run //tools/desktop-package:package-desktop -- \
  --archive bazel-bin/apps/desktop/vitruvian/Vitruvian.zip \
  --version 3.37.1 \
  --dist-dir apps/desktop/vitruvian/dist

# Dry-run validation (builds and validates artifacts locally without publishing):
bazel run //tools/desktop-package:package-desktop -- \
  --app-path dist/HomeSpeaker.app \
  --version 1.11.0 \
  --dry-run
```

### Options

| Flag | Description | Default |
|---|---|---|
| `--app-path <path>` | Path to pre-built `.app` bundle | Required if `--archive` omitted |
| `--archive <path>` | Path to `.zip` containing `.app` bundle | Required if `--app-path` omitted |
| `--app-name <name>` | Application display/bundle name | Inferred from `.app` bundle |
| `--version <ver>` | Application release semver | Inferred from `Info.plist` or tag |
| `--dist-dir <dir>` | Directory to stage release artifacts | `./dist` |
| `--cask-name <name>` | Homebrew cask identifier (kebab-case) | Inferred from `--app-name` |
| `--cask-desc <desc>` | Description for Homebrew Cask formula | Generated default |
| `--cask-homepage <url>` | Homepage for Homebrew Cask formula | Repo component URL |
| `--entitlements <path>` | Entitlements plist for code signing | None |
| `--repo <owner/repo>` | Target GitHub repository | `VitruvianSoftware/vitruvian-core` |
| `--tag <tag>` | Target GitHub Release tag | Ambient `TAG` / `RELEASE_TAG` |
| `--skip-signing` | Skip codesigning (testing only) | `false` |
| `--skip-dmg` | Skip DMG creation (headless/testing) | `false` |
| `--skip-thinning` | Skip lipo thinning to arm64/x86_64 | `false` |
| `--sync-downloads` | Run `sync_downloads.py` after packaging | `false` |
| `--dry-run` | Package and verify; do not upload/push | `false` |

---

## Environment Variables

When running in CI (`delivery-<app>.yaml` or `<app>-release.yaml`):

- `SIGNING_IDENTITY` / ambient Developer ID: Codesigns nested binaries and bundle (falls back to ad-hoc when absent).
- `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `NOTARY_API_KEY_P8`: Apple Notary Service API credentials for automated notarization and stapling.
- `HOMEBREW_TAP_TOKEN`: GitHub App or Personal Access Token with write permissions to `VitruvianSoftware/homebrew-tap`.
- `GH_TOKEN`: Token for GitHub release asset uploads.

---

## Testing

Hermetic unit tests for pure library helpers and dry-run flows are executed via Bazel:

```bash
bazel test //tools/desktop-package/...
```
