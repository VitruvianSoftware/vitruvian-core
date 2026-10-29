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
| `--require-asset <name>` | Also require `<name>` and `<name>.sha256` among the artifacts (repeatable). For a file the caller puts in `--dist-dir` itself, named `<App>-<version>*.zip` or `*.dmg` so it is checksummed and uploaded | None |
| `--verify-only` | Package nothing; only check the expected artifacts exist (see below). Needs `--app-name` and `--version` or `--tag` | `false` |

### A run proves its own result

Before it finishes, and before the Homebrew cask is pushed, the tool checks that every expected artifact exists and is not empty: the app artifacts the skip flags leave, each with its `.sha256`, plus every `--require-asset`. In a dry run, or with no tag, it looks in `--dist-dir`. On a real release it reads the list back from the GitHub Release. Anything missing is named and the run exits non-zero. A run that stops before its last line also exits non-zero, whatever stopped it.

A release workflow should end with the same check as its own step, so the job's result does not rest on the publishing script alone:

```bash
bazel run //tools/desktop-package:package-desktop -- --verify-only \
  --app-name HomeSpeaker --version 1.13.1 --tag home-speaker-v1.13.1 \
  --require-asset HomeSpeaker-1.13.1-tool.zip
```

### Writing a script that calls this tool

Release runners are Macs, and a Mac's `/bin/bash` is 3.2. Two things differ from the bash on Linux and on most laptops, and together they shipped HomeSpeaker 1.12.0 and 1.13.0 with no files and a green run:

- Expanding an **empty** array under `set -u` ends the script (`unbound variable`). Write `${args[@]+"${args[@]}"}`, never a bare `"${args[@]}"`, for any array that can be empty.
- After that kind of abort an `EXIT` trap runs with `$?` equal to 0, and the script exits with the trap's status. A trap that only cleans up turns the abort into exit 0. Set a flag on the script's last line and have the trap exit non-zero without it.

`//tools/desktop-package:package-desktop_test` and `//apps/desktop/home-speaker:publish_test` check both; copy the shape for a new app.

---

## Environment Variables

When running in CI (`delivery-<app>.yaml` or `<app>-release.yaml`):

- `SIGNING_IDENTITY` / ambient Developer ID: Codesigns nested binaries and bundle (falls back to ad-hoc when absent).
- `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `NOTARY_API_KEY_P8`: Apple Notary Service API credentials for automated notarization and stapling. `NOTARY_API_KEY_P8` may be the `.p8` key itself or its base64, which is how the `VITRUVIAN_NOTARY_API_KEY_P8` secret holds it (see `//tools/apple-signing`). An `.app` is zipped before it is submitted, and the ticket is stapled to the `.app`.
- `HOMEBREW_TAP_TOKEN`: GitHub App or Personal Access Token with write permissions to `VitruvianSoftware/homebrew-tap`.
- `GH_TOKEN`: Token for GitHub release asset uploads.

---

## Testing

Hermetic unit tests for pure library helpers and dry-run flows are executed via Bazel:

```bash
bazel test //tools/desktop-package/...
```

The test also runs the real driver with stand-ins for `codesign`, `gh` and `python3`, under every bash on the machine. On Linux that is a recent bash, which cannot reproduce the bash 3.2 failures; there a static check (no bare `"${array[@]}"`) and planted failures stand in. The run that proves the bash 3.2 case is the macOS lane in `ci.yaml`, which names the test with `REQUIRE_BASH32=1` so it fails if no bash 3 is found.
