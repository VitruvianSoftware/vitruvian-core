# Upstream provenance

This directory is a fork of **vorssaint-utils**, a macOS menu-bar utility app.

| | |
| --- | --- |
| Upstream | <https://github.com/vorssaint/vorssaint-utils> |
| Imported commit | `aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958` (2026-10-02, "chore(agents): update AI price list") |
| Upstream version at import | 3.4.1-beta.1 (build 96) |
| Imported on | 2026-10-02 |
| License | GPL-3.0-or-later (see [`LICENSE`](LICENSE)) |

## Licensing: this directory is GPL, not Apache

The monorepo is Apache-2.0, but **everything under `apps/desktop/vitruvian/` is
GPL-3.0-or-later**, including the files added here (BUILD, `bazel/`, docs). The
upstream project has many contributors, so it cannot be relicensed.

What that means in practice:

- Keep every upstream `SPDX-License-Identifier` / `Copyright (C) 2026 Vorssaint`
  header exactly as it is. New files in this directory carry
  `GPL-3.0-or-later` with a VitruvianSoftware copyright line.
- Code from this directory must not be copied into Apache-licensed parts of the
  monorepo, and Apache-licensed targets must not link against it. The `BUILD`
  file keeps every target private for that reason.
- Distributing a build, including to testers, obliges us to offer the complete
  corresponding source under the GPL. A Copybara export of this directory to a
  public mirror is the natural way to do that, and the mirror has to be in place
  before the first build goes out.

## Trademarks and release blockers

Upstream's [`TRADEMARKS.md`](TRADEMARKS.md) reserves the Vorssaint name, logo,
icon, bundle identity, signing identity and update feed for upstream. The rename
(2026-10-02) replaced them:

- **Name:** Vitruvian everywhere the app shows or reads it. Upstream's
  copyright lines stay, because they are legal notices, not branding (GPL-3.0 §5).
- **Bundle IDs:** `com.vitruviansoftware.vitruvian`, plus its fan helper and Now
  Playing adapter IDs.
- **Icon:** the placeholder mark described below.
- **Update feed and price list:** the planned public mirror
  `VitruvianSoftware/vitruvian`. It does not exist yet, so update checks find
  nothing and prices fall back to the bundled list.
- **Temporary links and feedback:** these were upstream's own servers. They now
  target reserved `.invalid` hosts (RFC 6761) and fail closed, so no capture or
  report leaves the Mac.
- **Donation, Discord and X:** `AppInfo.hasCommunityChannels` is `false`. That
  hides the Support settings page and upstream's post-update support prompt, and
  the remaining links point at the repository.
- **Upstream migrations removed:** the fork must never act on an upstream
  install. `BundleMigration` (it renamed or removed old Vorssaint bundles) is
  deleted, and `build.sh` and `Tools/uninstall.sh` no longer touch legacy
  upstream app paths. The Cleaner also protects upstream's data namespaces.

**Still blocking a first release:**

- The public mirror `VitruvianSoftware/vitruvian`. The GPL requires offering the
  source with every build, and the update feed points there.
- Real artwork to replace the placeholder icon and mark. Re-record
  `Resources/Gifs/*.gif` from the renamed app: they still show upstream's planet
  mark.
- A Developer ID signing identity and the release pipeline.
- A decision on whether to run our own temporary-link and feedback backends, or
  remove those features and their dead UI in the refactor.
- `CHANGELOG.md` is upstream's history, shown in-app under Release notes. Start
  Vitruvian's own changelog at its first version.

## What the import left out

The import is the upstream tree at the commit above. Every file kept is byte for
byte identical to upstream except `.gitignore` (listed below). Left out:

- `Resources/Brand/`: upstream's logo, app icon and Icon Composer project.
  Upstream reserves this artwork as brand material and does not license it
  under the GPL (its SVG says so in its metadata, and see `TRADEMARKS.md`), so we
  have no licence to copy it. In its place, `Resources/Brand/` holds original
  placeholder artwork with the same file names, drawn by
  `Resources/Brand/make_placeholder_brand.py`. Design should replace it.
- `.github/`: upstream CI, release and issue workflows. The monorepo pipeline
  replaces them.
- `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `SUPPORT.md` and
  `docs/AI-CONTRIBUTIONS.md`: upstream's own contact points and processes.
  `README.md` and `AGENTS.md` here replace them.
- `docs/assets/`, `docs/demo.gif` and `ReleaseAssets/`: marketing screenshots
  and videos (about 45 MB) that are not used by the build or the tests.

## Modifications

GPL-3.0 §5(a) requires a notice that the work was modified, with a date. This log
is that notice. Add an entry for every change to upstream files.

- **2026-10-02**: Imported. Added `BUILD`, `bazel/`, `UPSTREAM.md`,
  `README.md` and `AGENTS.md`. In `.gitignore`, dropped the `AGENTS.md` entry so
  the nested agent guide can be committed. Replaced the reserved brand artwork
  in `Resources/Brand/` with generated placeholders.
- **2026-10-02**: Renamed to Vitruvian (see "Trademarks and release blockers"):
  - names, bundle IDs, module and source paths (`Sources/Vorssaint` became
    `Sources/Vitruvian`), keys and namespaces;
  - upstream servers, feeds and community links replaced or disabled;
  - `BundleMigration.swift` deleted, and the legacy-app cleanup in `build.sh` and
    `Tools/uninstall.sh` dropped;
  - tests that pinned upstream's links and support prompt updated.

  Copyright notices, `LICENSE`, `TRADEMARKS.md` and `CHANGELOG.md` are unchanged.
- **2026-10-02**: Refactor step 1 (`REFACTOR.md`):
  - `FeatureRuntime`'s bindings dictionary became an exhaustive switch, adding
    the missing `connectedDevices` binding;
  - `AppDelegate`'s permission re-sync lists now come from
    `AppFeature.dependents(on:)`;
  - tests updated.

## Syncing from upstream

There is no automatic sync. To take a later upstream commit:

1. `git archive` that commit into a scratch directory and drop the paths listed
   above.
2. Diff it against this directory. Port the changes, keeping this repo's own
   modifications.
3. Run `bazel run //apps/desktop/vitruvian:sync_sources` (in case `build.sh`
   changed its source lists), then build and test (see `README.md`).
4. Update the commit and version in the table above, and add an entry under
   Modifications.

Once the refactor diverges from upstream, cherry-picking individual fixes will
be more practical than taking whole commits.
