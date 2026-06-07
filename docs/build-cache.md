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

## Or configure it by hand

`user.bazelrc.example` lists the same options as copy-paste lines. Copy this repo's
`user.bazelrc.example` to `user.bazelrc` and uncomment the one you want:

```bazelrc
# local — this machine only
common --disk_cache=/absolute/path/to/cache

# shared — your team's bazel-remote (read-only; CI writes)
common --remote_cache=grpcs://cache.example.com
common --remote_upload_local_results=false

# buildbuddy — cache + remote execution (see docs/remote-build.md)
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
