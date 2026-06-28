# Dependency Versioning & the One Version Rule

This monorepo manages third-party dependencies with **one resolved version per ecosystem** —
the *One Version Rule* (1VR). For each language, external packages flow through a single shared
"hub": one `pip` lock, one `maven_install.json`, one `go.work`/`go.sum`, one `pnpm-lock.yaml`,
one `Cargo.lock`, one `Gemfile.lock`. Bazel builds everything in that hub against the same
versions.

1VR is a feature, not a limitation. It keeps the build graph small, makes an upgrade a single
decision instead of a per-app negotiation, and surfaces conflicts at build time rather than as
runtime surprises in production. But it raises the obvious question this guide answers:

> What happens when two apps in the same language genuinely need *different* versions of the
> same library — or when one app is held back because a transitive dependency it relies on
> hasn't upgraded yet?

This page is the language-agnostic model. For the exact mechanics — and the escape hatches — in
your stack, see the [per-language pages](#per-language-guides) below.

```mermaid
flowchart LR
    subgraph ovr["One Version Rule (default)"]
        direction LR
        a1["app A"] --> hub[("pip hub — one lock")]
        a2["app B"] --> hub
        a3["app C"] --> hub
        hub --> v(["one version of each package"])
    end
    subgraph div["Deliberate divergence (separate closures)"]
        direction LR
        b1["app A"] --> h1[("@pip")]
        b2["app B (needs older dep)"] --> h2[("@pip_legacy")]
    end
```

## The mental model: two kinds of resolver

Every package manager falls into one of two camps, and which camp a language is in decides what
"different versions" even means:

- **Nesting resolvers** keep multiple versions side by side. A diamond just dissolves: a library
  gets `X@1`, your app gets `X@2`, and both are built. The cost is duplication, plus the rare
  "two types that look identical but aren't" error when a value of one version crosses an API
  boundary expecting the other.
- **Flat resolvers** allow exactly one version of a package in a given closure. Two incompatible
  requirements are a hard conflict: one version must win, and a single lagging transitive
  dependency can hold the whole tree back.

Your per-language page states which camp that language is in and what it does on conflict.

## The diamond / transitive-lag problem

The painful version of this isn't "app A wants v1, app B wants v2" — that's a deliberate choice.
It's the *involuntary* one: app B needs `X@2`, but library `Y` (which some app depends on) still
pins `X@1` because `Y` hasn't cut a release that widens its constraint.

- In a **nesting** ecosystem this is a non-event — `Y` keeps its `X@1`, app B gets `X@2`.
- In a **flat** ecosystem the laggard effectively pins everyone: the resolver either fails
  outright, or silently picks one version and you discover the mismatch as a runtime error. This
  is exactly the pain 1VR makes you feel *early*, at build time, instead of in prod.

```mermaid
flowchart TB
    subgraph nest["Nesting resolver (pnpm, Cargo) — diamond dissolves"]
        direction TB
        nA["app"] --> nX2["X v2"]
        nA --> nY["lib Y (laggard)"]
        nY --> nX1["X v1"]
    end
    subgraph flat["Flat resolver (pip, Maven, Bundler, Go) — one winner"]
        direction TB
        fA["app"] --> fX["X v2 (single winner)"]
        fA --> fY["lib Y (laggard)"]
        fY -. "still needs X v1" .-> fX
        fX --> boom("Y breaks if incompatible: resolve fails or runtime error")
    end
```

## Decision tree: when versions diverge

```mermaid
flowchart TD
    A["Two apps need different versions of the same library"] --> B{"Can you converge? (bump the laggard or pin one version)"}
    B -->|Yes| C(["Converge — the default, cheapest path"])
    B -->|No| D{"Nesting ecosystem? (pnpm, Cargo, Go across majors)"}
    D -->|Yes| E(["Declare both versions — they coexist for free"])
    D -->|"No, flat"| F{"Must both live in the same binary / process?"}
    F -->|"No, separate binaries"| G(["Separate closures: 2nd pip hub, named maven install, or a module out of go.work"])
    F -->|"Yes, same binary"| H(["Shade / relocate, vendor, or split into separate processes"])
    H -.->|Copybara| I(["Or publish to a standalone repo with its own dependency closure"])
```

1. **Can you converge?** Prefer it, every time. Bump the lagging consumer, or force the shared
   dependency to one version and run the tests. Convergence is usually possible and always
   cheaper than maintaining parallel versions. This is the default and the reason 1VR exists.
2. **Is it a nesting ecosystem?** (JavaScript/pnpm, Rust/Cargo, Go across major versions.) Then
   divergence is essentially free — declare the versions you need and move on.
3. **Do you genuinely need divergence in a flat ecosystem?** Give each app its own closure: a
   second `pip` hub, a named `maven` install, or a module pulled out of `go.work`. The two apps
   stop sharing that dependency. See the per-language page for the exact wiring.
4. **Must both versions live in the *same* binary?** (one JVM classpath, one Python interpreter,
   one linked binary.) Separate hubs won't save you here — you need shading/relocation,
   vendoring, or to split the work into separate processes. Or publish the app to its own
   standalone repo, which gets a fully independent dependency closure (see below).

## Detecting a conflict

Start by asking the resolver who pulled a package in and which version won. The command is
language-specific — each per-language page lists it (`pnpm why`, `go mod why`, `cargo tree -d`,
`bundle why`, the Maven dependency tree, etc.). In every case the goal is the same: find the
*laggard* constraint, then decide converge vs. isolate using the tree above.

## Where each ecosystem declares its versions

1VR is about *resolution* — one resolved version per hub. Its companion is *declaration*: the
one place you edit to bump a version, so the same dependency can't be pinned at drifting ranges
across projects. Every ecosystem here has a single declaration hub; this table is the source of
truth for "where do I change a version."

| Ecosystem | Declaration hub | Mechanism | Status |
|---|---|---|---|
| Bazel modules | `MODULE.bazel` | one `bazel_dep(name, version)` per dep | centralized by construction |
| Python | `requirements/*.in` → `requirements/all.txt` | one compiled `pip.parse` lock | centralized by construction |
| Rust | root `Cargo.toml` | `[workspace.dependencies]` + `Cargo.lock` | centralized by construction (workspace currently empty) |
| Go | `go.work` members' `go.mod` | MVS over the workspace; Bazel reads `//:go.work` | resolution centralized; declarations per-module — keep shared deps converged |
| JavaScript / TypeScript | `pnpm-workspace.yaml` `catalog:` | catalog entries referenced as `"catalog:"` | adopting — migrate shared deps off per-`package.json` ranges |

Bazel, Python, and Rust centralize declaration by design. Go centralizes *resolution* through
`go.work` but still declares versions per-module, so converge shared dependencies across members
rather than letting them drift. JavaScript centralizes declaration with pnpm **catalogs** (see
[javascript.md](javascript.md)); the migration is incremental — uniform tooling first, then
shared frameworks via named catalogs.

## Per-language guides

- [Python](python.md) — `rules_python` `pip.parse` hubs (flat)
- [JavaScript / TypeScript](javascript.md) — `aspect_rules_js` + pnpm (nesting)
- [Go](go.md) — `rules_go` + `go.work` + MVS (flat within a major)
- [Java](java.md) — `rules_jvm_external` / Maven (flat classpath)
- [Kotlin](kotlin.md) — `rules_kotlin` + Maven (flat classpath)
- [Scala](scala.md) — `rules_scala` + Maven (flat classpath)
- [Rust](rust.md) — `rules_rust` + crate universe / Cargo (nesting)
- [C / C++](cpp.md) — `bazel_dep` / `http_archive` repos (one-version, ODR)
- [Ruby](ruby.md) — `rules_ruby` + Bundler (flat)
- [Swift](swift.md) — `rules_swift` + Swift packages (one-version)

## Escape hatch: standalone repos

This repo syncs components out to standalone repositories with Copybara (see
[copybara-bidi-sync.md](copybara-bidi-sync.md)). That sync is also your ultimate version-
isolation boundary: each synced component builds independently in its own repo with its **own**
dependency closure (its own lockfile), separate from the monorepo's shared hubs.

```mermaid
flowchart LR
    subgraph mono["monorepo (One Version Rule)"]
        direction TB
        cA["component A"] --> hub[("shared hubs: @pip @maven @npm")]
        cB["component B"] --> hub
    end
    mono -. "Copybara sync" .-> std["standalone repo: component B<br/>its own lockfile and versions"]
```

So if two apps have irreconcilable version needs and don't share code, the standalone repo gives
each a clean, isolated set of versions for free — the One Version Rule pressure only applies
*inside* the monorepo. The trade-off is the usual one: a component that diverges this way no
longer benefits from the monorepo's single-version coherence, so reserve it for genuine
irreconcilable cases rather than as a routine escape from convergence.
