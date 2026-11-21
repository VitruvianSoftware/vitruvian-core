---
status: approved
---

# Shared packages: one layout, one catalog, reuse before writing

## In short

The repo has shared libraries, but nobody can find them, so tools keep writing their own
copies. About 30 internal tools each carry a private copy of the same small Rust helpers
(JSON, command-line options, text handling), roughly 30,000 lines in all. This design does
three things:

1. **One layout for `packages/`**: one folder per package, named for what it does.
2. **One catalog everyone can search**: Backstage, reachable by every agent through its MCP
   server, with a generated `packages/README.md` table as the offline fallback. Both are
   built from the same `catalog-info.yaml` files, and CI keeps them complete.
3. **Reuse before writing**: agents and people check our packages first, then a well-known
   third-party library, and write new code only when neither fits. A CI check flags new
   copies of code that already exists in a package.

It also says where the existing duplicated helpers go.

## The problem, measured

All numbers are from `origin/main` on 2026-11-20.

- **Copies of the same helpers.** Leaving out tests, these are the private copies in tools
  outside the shared packages:

  | Helper | What it does | Copies | Code lines | Also in another copy |
  |---|---|---|---|---|
  | `json` | read and write JSON | 16 | 9,246 | 71% |
  | `argparse` | command-line options | 5 | 2,996 | 84% |
  | `unicode_tables` | character tables | 4 | 4,518 | 58% |
  | `jq` | JSON queries | 7 | 2,077 | 50% |
  | `http` | web calls through curl | 8 | 3,188 | 44% |
  | `pystr` | Python-style text | 10 | 3,298 | 51% |
  | `pyjson` | Python-style JSON output | 5 | 1,750 | 42% |
  | `pyerr` | Python-style errors | 8 | 825 | 65% |
  | `gostd`, `goexec` | Go-style helpers | 5 | 1,871 | 34–100% |

  Up to about 18,000 of those lines repeat another copy. The real saving is smaller,
  because the parts each tool changed must be kept or reconciled.
- **The index is empty of content.** `packages/README.md` is generated, but each entry just
  says "Contract for packages/X". It leaves out `packages/rust/` and `packages/swift/`
  entirely, so the shared Rust and Swift libraries do not appear.
- **Backstage is incomplete.** It lists 33 components, and only 3 are libraries
  (`design-system-android`, `pulumi-library-go`, `pulumi-library-ts`). Seven of the nine
  `packages/` folders have no `catalog-info.yaml`, and neither do several products
  (Atrium, Courier, Speaker, Watch, Relay, gods-eye-view, ostation). The cause is
  structural: Backstage reads one root `catalog-info.yaml` whose list of targets is edited by
  hand, so every new folder has to remember to add itself.
- **Nothing tells agents to look first.** `AGENTS.md` has no rule to check for an existing
  library before writing one, and nothing catches a new copy before it merges. Most of the
  copies above were written by agents porting tools from Python and Go.
- **Hand-written path lists already drift.** `ci.yaml`'s `detect-macos` filter decides
  whether a change needs the Mac app build from a hand-written folder list. It does not list
  `packages/swift/SentryLite` (used by five Mac apps and extensions) or
  `packages/vitruvian-sdk` (used by four). Not yet checked: whether another workflow, such as Presubmit's dependency-graph
  planner, already builds those apps when one of these packages changes.

## Goals

- A developer or agent can answer "do we already have X?" in one search, and trust the
  answer.
- Nothing about discovery is maintained by hand, so it cannot drift.
- New duplicates are caught at review time, not found months later by a scan.
- The layout keeps our path-based pipeline rules (release scope, exports, owners, filters)
  accurate and cheap as the repo grows.

Not goals: changing how Bazel builds or tests things, or moving product code.

## Decision 1: one folder per package, named for what it does

```
packages/
  README.md               generated index, plus a short hand-written header
  <what-it-does>/         kebab-case: pycompat, mcp-auth, design-system, sentry-lite
    README.md             what it gives you, when to use it, when not to, an example
    catalog-info.yaml     Backstage entry, type: library (the index is built from these)
    BUILD                 the targets other code depends on
    <language>/           only when the package has more than one language
```

Rules:

- **Named for the job, not the language or the company.** `mcp-auth`, not `rust/` or
  `vitruvian-mcp-auth`. A crate or module inside can keep its own name (`vitruvian_pycompat`).
- **No grab-bags.** No `utils`, `common`, `misc` or `shared`. If a name needs "and", it is
  two packages.
- **Language subfolders only inside a package.** For example `design-system/web` and
  `design-system/android`, or `pulumi/library/go` and `pulumi/library/ts`, which already
  works this way.

### Why purpose first, not language first

We looked at both. Purpose first wins on three counts.

1. **Our packages already span languages.** `vitruvian-sdk` is Rust, Swift and Go. `pulumi`
   is Go and TypeScript. The design system exists for web and Android. Language folders
   would split each of these across two or three places.
2. **Our pipelines key on folders.** Two kinds of rule decide what a change touches:
   - The Bazel dependency graph (the presubmit planner). It follows dependencies, so the
     layout does not matter to it.
   - Path rules: release-please and `release-scope` (one product per folder), workflow path
     filters, Copybara exports, CODEOWNERS. These work best when one package is exactly one
     folder: one owner, one release, one export, one filter line. Under language-first, a
     design-system change touching web and Android counts as two products to release and
     needs two owners and two filter entries.

   The one thing language folders offer is a broad filter like `packages/swift/**`. The Mac
   filter above shows that hand-written filters drift either way. Decision 7 replaces them
   with filters generated from the Bazel graph.
3. **It matches how Google's monorepo treats shared code.** Google's published guidance
   keeps all outside code in one place, `//third_party`, under a one-version rule, and uses
   language-specific folders only inside it, such as `third_party/java` (sources at the
   end). We already follow the one-version rule (`docs/dependency-versioning/`). From
   memory, not confirmed in a published source: Google's own code is organized by project
   and owning team, with an OWNERS file per folder, and Java is the exception because the
   language requires `java/com/google/...` paths.

### Renames this implies

| Today | Becomes |
|---|---|
| `packages/rust/vitruvian-pycompat`, `packages/rust/vitruvian-pyjson` | `packages/pycompat/` (two crates in one package) |
| `packages/rust/vitruvian-mcp-auth` | `packages/mcp-auth/` |
| `packages/swift/SentryLite` | `packages/sentry-lite/` |
| `packages/design-system`, `packages/design-system-android` | `packages/design-system/web`, `packages/design-system/android` |
| everything else | unchanged |

Each rename is its own pull request, done last (see the rollout plan). Bazel labels, build
paths, the Slack MCP Copybara export and two workflows point at the current paths. The
workflow changes need James's approval.

## Decision 2: what belongs in `packages/`

- **Used by two or more products** → `packages/`.
- **Shared only inside one product** → stays in that product. `tools/gitops/values-yaml`
  serves only the gitops tools, so it stays there.
- **Used by one product today, but meant for others** → `packages/`, with a consumer named
  in its README.
- **Outside code** → never copied in. It is a dependency in the lockfiles (`MODULE.bazel`,
  `Cargo.toml`, `package.json`), under the one-version rule.

## Decision 3: what every package must have

- **`README.md`** with these sections: what it gives you (one paragraph); when to use it;
  when not to (and what to use instead); a short example; the Bazel target to depend on;
  constraints (for example "standard library only, because it is also built with plain
  `rustc`").
- **`catalog-info.yaml`**, a Backstage `Component` with:
  - `spec.type: library`, `spec.owner`, `spec.lifecycle`;
  - `metadata.description`: one sentence on what it gives you;
  - `metadata.tags`: its languages (`rust`, `swift`, `go`, `typescript`, `kotlin`) and
    what it does (`json`, `cli`, `auth`, `ui`, …), which is what search matches on;
  - the annotation `vitruvian.dev/bazel-target`, so a reader knows what to depend on.
- **A public Bazel target**, with every other target in the package kept private.

A CI check enforces all three (Decision 5).

## Decision 4: Backstage is where you look, `packages/README.md` is the fallback

- **Backstage is the main search.** It answers more than a file can: who owns a package,
  what depends on it, its docs. Agents reach it through its MCP server
  (`@backstage/plugin-mcp-actions-backend`, already installed). Queried from a Claude Code
  session on 2026-11-20, it answered correctly.
- **Every agent gets the MCP server, not only one Mac's sessions.** Today it is set up only
  in one user's Claude Code configuration. Specialist agents (Gemini through Antigravity),
  cloud sessions, OpenCode and CI do not have it. The fix is to declare it in the repo's own
  agent configuration for each tool that supports MCP. Agents that run unattended need a
  read-only service sign-in to Backstage, stored with the other agent secrets and never in
  git.
- **`packages/README.md` is the fallback**, for agents and CI jobs with no MCP or no
  network. It has two parts:
  - a short hand-written header that rarely changes: how to search (Backstage, or this
    table), the reuse order from Decision 6, and how to add a package;
  - a table generated from every `catalog-info.yaml` under `packages/`: name, what it gives
    you, languages, Bazel target, owner. A drift test fails when the table is stale, the
    same pattern the repo uses for its other generated files.

  Both views come from the same `catalog-info.yaml` files, so they cannot disagree.

## Decision 5: keep Backstage complete automatically

- **Backstage finds catalog files itself.** Replace the hand-edited root list with the
  GitHub entity provider from `@backstage/plugin-catalog-backend-module-github` (installed,
  `^0.14.0`). Pointed at `catalogPath: /**/catalog-info.yaml`, it finds every file on its own
  schedule. To confirm while implementing: that this version supports a glob there, and how
  the provider and the existing `githubOrg` provider share a schedule.
- **CI refuses a folder with no entry.** A check (`//tools/conformance` or a new target)
  fails a pull request when any package under `packages/`, or any product folder under
  `apps/`, has no valid `catalog-info.yaml`. It also requires the fields in Decision 3.
- **New things start registered.** `//tools/initializer` already writes `catalog-info.yaml`
  for new apps. It gets a "new package" template that writes the README skeleton,
  `catalog-info.yaml` and `BUILD` too.
- **Backfill once**: the 7 packages and the products listed above get their entries in the
  first rollout step.

## Decision 6: reuse before writing

Agents and people follow the same order:

1. **Our own packages** (search Backstage, or `packages/README.md`).
2. **A third-party library we already depend on** (check the lockfiles).
3. **A new third-party library** that is well known, actively maintained and widely used,
   with a compatible license, and that passes `//tools/osv-scan`. Add it as the one version
   for its ecosystem.
4. **New code**, only when none of those fits. If two products will use it, it goes in
   `packages/` (Decision 2).

Why our packages come before third-party ones: a new dependency costs real work here (the
one-version rule, license checks, vulnerability scans, lockfile upkeep), and our packages
have already paid it. Some also exist because of constraints a typical library does not
meet: `pycompat` must behave exactly like the Python tools it replaced, and builds with
plain `rustc`, outside Bazel.

This goes in `AGENTS.md` under "Build, test, run", in the same words, so every agent tool
reads it.

## Decision 7: catch duplicates and drift in CI

- **A duplication check.** A new target compares the code a pull request adds against
  `packages/`. It reports any block of about 12 or more meaningful lines that already exists
  in a package, and names the package to use instead. It starts as a warning, and becomes
  blocking once the backlog below is cleared. The scanner used to measure the table above
  is the prototype.
- **Path filters generated from the Bazel graph.** Hand-written lists like `detect-macos`
  are generated from the dependency graph (for example, every folder that a macOS target
  depends on), with a drift test. That also fixes the SentryLite and SDK gap above, if
  it turns out to be real.

## Where the existing duplicates go

| Helper | Destination | Notes |
|---|---|---|
| `argparse`, `unicode_tables`, `json`, `pystr` | `pycompat` | It already has the shared copy of each. |
| `pyerr`, `http` | `pycompat` (new modules) | Standard library only, like the rest of the package. `http` shells out to curl. |
| `pyjson` | `pycompat` (its serde crate) | Already holds the shared copy. |
| `jq` | new `packages/jq/` | Built on serde_json, so tools that do not need it do not take on that dependency. |
| `goexec`, `gostd` | new `packages/gocompat/` | Mimics Go's standard library, not Python's. |

Each tool switches to a one-line re-export (`pub use vitruvian_pycompat::json;`) and keeps
its own call sites unchanged, as #4998 did. Order: `goexec` and `argparse` (nearly
identical), then `unicode_tables` (the #5005 pattern, with its every-character equivalence
test), then `json`, then `jq`, and `http` plus the `py*` text helpers last, since their
copies differ the most.

Deliberate copies that stay:

- the orchestrator core's three plugin copies, generated from `packages/orchestrator-core`
  by `tools/agent-roster` because each plugin installs on its own;
- the Pulumi foundation example, a published reference copy of the live foundation;
- oauth-user-inspector's design-system files, because that app also ships as its own repo;
- the Antigravity plugins' identical JSON helper, kept in step by a test;
- generated Pulumi SDK code.

## Rollout

Each step is its own pull request, and each works with today's folders, so nothing waits on
the renames.

1. **Check the Mac filter gap.** Confirm whether a change to `packages/swift/SentryLite` or
   `packages/vitruvian-sdk` builds the Mac apps that use them. If not, add them to the filter
   now (needs James's approval: `.github/workflows/**`).
2. **Backfill catalog entries and the package contract.** Add `catalog-info.yaml` and
   README sections for every package and the missing products.
3. **Catalog check in CI and the "new package" initializer template.**
4. **Backstage auto-discovery** (`apps/web/backstage/app-config.yaml`), then remove the
   hand-edited root list.
5. **Generated `packages/README.md`** with its drift test.
6. **The reuse order in `AGENTS.md`.**
7. **The Backstage MCP server for every agent tool**, with the read-only service sign-in.
8. **The duplication check**, as a warning.
9. **Consolidate the helpers**, one family per pull request, in the order above. Changes
   inside `tools/agent-guard` need James's approval. Each pull request also updates the
   plain-`rustc` builds that use the moved code, as #4998 did.
10. **Renames**, one package per pull request.
11. **Make the duplication check blocking**, and generate `detect-macos` from the graph.

## Approvals needed

- James approves this design.
- James approves on GitHub any pull request touching `.github/workflows/**` (steps 1, 10,
  11, and step 9 where a workflow builds with plain `rustc`) or `tools/agent-guard/**`
  (step 9).
- Step 7 needs a read-only Backstage sign-in for unattended agents.

## Alternatives considered

- **Language-first layout** (`packages/rust/`, `packages/swift/`, …). Rejected: it splits
  multi-language packages and multiplies path rules (Decision 1).
- **A generic README that only points to Backstage.** Rejected as the only source: agents
  without the MCP server, and CI, could not use it. Kept as the header of the generated
  README.
- **Backstage only, no file index.** Same reason. The generated table costs nothing to keep
  correct, because it is generated.
- **Third-party libraries before our own packages.** Rejected: it adds dependencies where an
  already-vetted package fits (Decision 6).

## Sources

- Google, [The One Version Rule](https://opensource.google/docs/thirdparty/oneversion/)
- Google, [Put the Code in (the Right) //third_party](https://opensource.google/documentation/reference/thirdparty/where)
- Google, [Third-party Java](https://opensource.google/docs/thirdparty/java)
- Measurements: a 12-line-window duplicate scan of `origin/main` and a per-family line
  comparison, run 2026-11-20; Backstage catalog queried through its MCP server the same day.
