---
status: in-progress
---

# Orchestrator: publish the three plugins (step 5 of 5)

Step 5 of 5 in making `vitruvian-orchestrator` a public plugin (1: team file #5223,
2: generic team #5228, 3: team setup #5273, 4: native engine #5241). The plugins are now
generic, so a stranger can use them in any repository. This step makes each one
installable and updatable outside this repository. Each harness is its own product with
its own version and release, and none waits for another.

## Where each one ships

| Harness | Install | Published from |
|---|---|---|
| Claude Code | `/plugin marketplace add VitruvianSoftware/vitruvian-core`, then `/plugin install vitruvian-orchestrator@vitruvian-core` | This repository, which is public. Its marketplace already lists the plugin. |
| Antigravity | `agy plugin install https://github.com/VitruvianSoftware/vitruvian-orchestrator-antigravity` | A new export-only mirror whose root is `apps/antigravity/plugins/vitruvian-orchestrator/`, the same shape as `gh-watch`. |
| OpenCode | `"plugin": ["<npm package>"]` in `opencode.json` | npm. Its own section below. |

## Versions and releases

Today every plugin's version is fixed by hand (Claude Code and Antigravity at 0.2.0) and has
not moved through weeks of changes. A harness that caches by version, as Claude Code does,
then never offers the update. So each plugin gets release-please, like the Antigravity
plugins already have:

- `release-please-config.json`, `.release-please-manifest.json` (starting at the current
  version) and `CHANGELOG.md` in each plugin's folder. The version is written into
  `.claude-plugin/plugin.json` (Claude Code) or `plugin.json` (Antigravity).
- Both folders join the `apps-release.yaml` matrix and its `paths`. That workflow file needs
  James's approval on the pull request.
- Antigravity's mirror carries a `.github/workflows/release.yml` copied from `gh-watch`: it
  tags `v<version>` and publishes a GitHub release from the changelog when an exported
  version has no tag yet.
- Each plugin's folder already holds its generated agents, skills and its own copy of
  `orchestrator-core`, so a change to the roster or the core changes the folder, which is
  what release-please and the export watch.

## The Antigravity mirror

Follows `docs/admin/copybara-sync.md` §8f, export-only:

- `sync.go`: a `vitruvian-orchestrator-antigravity` entry with `CreateRepo: true`.
- `copy.bara.sky`: a `COMPONENTS` entry (`SQUASH`, `export_only`, no `standalone_only`).
- `copybara-export-vitruvian-orchestrator-antigravity.yaml`, the smoketest list,
  `notify-ci-issues.yaml` `MIRRORS`, the Dependabot entry for the nested workflow folder,
  and `CODEOWNERS`.
- The plugin gains a `LICENSE` (MIT). Its `plugin.json` `repository` and the marketplace
  entries point at the mirror.
- Its MCP server is `node mcp/server.mjs` with no dependencies. The sidecar panel is static
  files. Nothing outside the folder is needed, so the mirror runs as it is.

## OpenCode on npm (a second pull request)

Decided from OpenCode's plugin docs and the `@opencode-ai/plugin` types. The open points
below are tested on OpenCode 2.3 before that pull request is opened.

- Package `@vitruviansoftware/opencode-vitruvian-orchestrator`, added with
  `"plugin": ["@vitruviansoftware/opencode-vitruvian-orchestrator"]`.
- `package.json` exports `./server` (`server.mjs`) and `./tui` (`tui.tsx`). A `config`
  hook in `server.mjs` registers the generic agents from `agents/*.md` and points the
  skills path at the package's `skills/`, so one entry brings everything.
- Published from a new export-only mirror, as every npm package here is: npm trusts the
  mirror's `release.yml`, never this repository (`docs/engineering/npm-trusted-publishing.md`).
- A new package name cannot have a trusted publisher until it exists. So James publishes
  the first version once, by hand, from a clone of the mirror (npm needs his 2FA). Then a
  `tools/registry-trust/bootstrap.tsv` row and `registry-trust:setup` hand every later
  release to CI.
- To test on 2.3 first: whether the `opencode.json` entry also loads the TUI part (the docs
  name `tui.json` and `cli.json` in different places), and whether `skills` is
  `{ paths: [...] }` or a plain list.

## Checks

- Each plugin's version-consistency test covers the new manifest, as for the other
  Antigravity plugins.
- `//tools/conformance` and the Copybara smoketest cover the new mirror.
- After merge: the first export lands on the mirror (`MONOREPO_REV_ID` matches), and a
  fresh `agy plugin install` from the mirror loads the plugin. Release-please opens a
  release pull request for each plugin.

## Out of scope

A Claude Code mirror. The monorepo's marketplace already works, and a second copy is one
more thing to keep in step.
