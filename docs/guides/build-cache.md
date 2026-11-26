# Build cache

Bazel can reuse work it (or your teammates, or CI) already did instead of rebuilding from
scratch after a `bazel clean`, a branch switch, or a fresh clone. Caching is **opt-in** —
nothing is enabled by default, so builds always work offline with zero setup.

## Pick a cache

Run the picker and choose:

```bash
bazel run //tools/remote:setup
```

| Option | What it does | Shared with the team? |
|--------|--------------|------------------------|
| **none** | No cache (the default). | — |
| **local** | A disk cache on your machine (`~/.cache/<repo>-bazel-disk`). | No |
| **shared** | A self-hosted [bazel-remote](https://github.com/buchgr/bazel-remote) server — read-only for you, CI writes. | Yes |
| **buildbuddy** | [BuildBuddy](https://www.buildbuddy.io/) — cache **and** remote execution. | Yes (vendor) |

Your choice is written to `user.bazelrc` (git-ignored, personal to you). Re-run the command
anytime to switch; pick **none** to turn caching off. If a remote cache is ever unreachable,
Bazel falls back to building locally — it never blocks you.

## BuildBuddy is the local *default* once configured (#506)

Choosing **buildbuddy** makes the shared cache the default for **every plain
`bazel build/run/test` on your machine** (`common --config=remotecache` in your
`user.bazelrc`): cache-only — execution stays local, RBE remains an explicit
`--config=remote` — and your local results **upload** so the whole team (and
CI) reuses them. A stale/revoked key degrades gracefully to warnings + a local
build; it never blocks you. Opt out with
`bazel run //tools/remote:setup -- --no-local-default`.

Worktrees created by `bazel run //tools/worktree` inherit your cache setup
automatically (the managed block is copied into the worktree's
`user.bazelrc`), and `bazel run //:doctor` warns when a machine has no cache
configured.

## Or configure it by hand

`user.bazelrc.example` lists the same options as copy-paste lines. Copy this repo's
`user.bazelrc.example` to `user.bazelrc` and uncomment the one you want:

```bazelrc
# local — this machine only
common --disk_cache=/absolute/path/to/cache

# shared — your team's bazel-remote (read-only; CI writes)
common --remote_cache=grpcs://cache.example.com
common --remote_upload_local_results=false

# buildbuddy — cache + remote execution (see docs/guides/remote-build.md)
common --config=remote
```

## Which should we use?

- **Individuals / quick win:** `local` — zero infrastructure; speeds up your own rebuilds.
- **Teams, no vendor lock-in:** `shared` (bazel-remote) — CI populates it, everyone downloads;
  one small self-hosted server, addressed by URL.
- **Want remote *execution* too** (offload compiles to a cluster): `buildbuddy` — see
  [remote-build.md](remote-build.md).

The recommended pattern is **CI writes, developers read**: your green CI runs become everyone's
cache hits, and a developer's local environment can't pollute the shared cache.

## CI download caches (`bazel-repo-cache.yaml`)

GitHub-hosted CI jobs restore three pre-warmed download caches via
[`.github/actions/setup-bazel`](../../.github/actions/setup-bazel/action.yml) (strictly
restore-only; self-hosted queue runners mount the persistent `vitruvian-queue-cache` PVC
instead):

- **Bazel repository archives** (`setup-bazel-1-<os>-<arch>-repository-full-<hash>` at
  `$HOME/.cache/bazel-repo`): external archives from Bazel's downloader.
- **Go modules** (`bazel-gomod-1-<os>-<arch>-<hash>` at `$HOME/.cache/bazel-gomod`):
  `cache/download` zips used by gazelle's `go_repository` via
  `GO_REPOSITORY_USE_HOST_MODCACHE=1` and `GOMODCACHE`, because `go_repository` invokes
  `go mod download` rather than Bazel's downloader.
- **LLVM linker `.debs`** (`ci-debs-1-linux-x64-<sha256s>` at `$HOME/.cache/ci-debs`):
  checksum-verified Ubuntu 24.04 `libicu74` and `libxml2` packages needed by `ld.lld` on
  Ubuntu 26.04+.

Only [`.github/workflows/bazel-repo-cache.yaml`](../../.github/workflows/bazel-repo-cache.yaml)
(via [`.github/actions/bazel-repo-cache-warm`](../../.github/actions/bazel-repo-cache-warm/action.yml))
proves offline completeness (`--repository_disable_download` + `--repo_env=GOPROXY=off`)
and saves these entries on `main`.

On the self-hosted queue runners, every pod shares one repo contents cache
(`~/.cache/bazel-repo/contents`, the unpacked repos). When two pods unpack the same
brand-new repo at the same moment, Bazel can fail one of them with `error moving repo
@@X into the repo contents cache: … (File exists)`. That happens after a dependency bump
that adds repos, in the merge queue. setup-bazel puts a small `bazel` wrapper first on
`PATH` there ([`bazel_race_retry.sh`](../../.github/actions/setup-bazel/bazel_race_retry.sh)).
It reruns a command that failed with exactly that error, up to 3 times, and leaves every
other result alone. A retry shows as a "Bazel repo contents cache race" warning on the run.

## Rust toolchain and bundled Node caches (write-once recovery)

GitHub Actions cache keys are **write-once**: GitHub never overwrites an existing cache
entry under the same key. If a cached Rust toolchain or bundled Node tarball entry is
damaged, the verification step (`verify_toolchain` or `shasum -a 256`) rejects and deletes
the local copy so the job reinstalls or re-downloads it for that run, and it will repeat
that fallback on every run until the damaged cache entry is dropped.

To drop a damaged cache entry:

1. Bump the `v1` segment in the affected cache key (for example, `v1` → `v2`) and update any
   mirrored copy in sync.
2. Merge the change to `main` so `main` warms a fresh cache entry under the new key.

This covers:

- [`.github/actions/rust-cache-dir/action.yml`](../../.github/actions/rust-cache-dir/action.yml) (`rustup-toolchain-v1-...`)
- [`.github/workflows/vitruvian-code-mirror-toolchain.yaml`](../../.github/workflows/vitruvian-code-mirror-toolchain.yaml) (`rustup-toolchain-v1-...`, `vitruvian-code-node-v1-...`)
- [`apps/desktop/vitruvian-code/.github/workflows/release.yml`](../../apps/desktop/vitruvian-code/.github/workflows/release.yml) (`rustup-toolchain-v1-...`, `vitruvian-code-node-v1-...`)

Because the standalone Vitruvian Code mirror runs its release workflow infrequently, GitHub
Actions may evict its cache entries between releases. The first release after an eviction
falls back to the checksummed Node download (`node.lock`) and pinned
`rustup toolchain install 1.98.1`, then saves fresh cache entries on `refs/heads/main`.
