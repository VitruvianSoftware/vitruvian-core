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

## Trademarks: rename before distributing

Upstream's [`TRADEMARKS.md`](TRADEMARKS.md) reserves the Vorssaint name, logo,
icon, bundle identity, signing identity and update feed. A modified build may
not be distributed under any of them. The imported code still uses all of them.
Nothing built here may be published until the rename to **Vitruvian** replaces:

- the name in `Resources/Info.plist`, the `*.lproj/InfoPlist.strings` files and
  the user-facing strings;
- the GIFs and images in `Resources/Gifs/` and `Resources/Images/` that show
  the old branding (the brand masters themselves were never imported; see below);
- the bundle identifier `com.vorssaint.utils` and its derived helper and adapter
  IDs (`BUILD`, the launchd plist, `Defaults` and test-suite namespaces);
- the update feed (`Services/Update/UpdateService.swift` checks
  `vorssaint/vorssaint-utils` releases) and the remote price list
  (`Services/AgentUsage/AgentPriceSource.swift`).

Until then, CI only builds and tests the app, and uploads no artifacts.

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
