---
status: completed
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
| OpenCode | `"plugins": ["@vitruviansoftware/opencode-vitruvian-orchestrator"]` in `opencode.json` | npm, from a new export-only mirror `vitruvian-orchestrator-opencode`. Its own section below. |

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

Tested on OpenCode 2.3.2 with the real plugin staged the way npm installs it
(no `node_modules`), before writing the code:

- The config key is `plugins` (a list). One entry loads the package's
  `./server` export and its `./tui` export: the sidebar needs no `tui.json`.
  OpenCode supplies `solid-js` to the sidebar, so the package has no
  dependencies.
- OpenCode never reads agent or skill files inside a plugin. A server plugin
  adds them itself: `ctx.skill.transform(editor => editor.add({ id, name,
  description, path, content }))`, and, since the agent editor has no `add`,
  `ctx.agent.transform(editor => editor.update(id, draft => { ... }))`, which
  creates a missing agent from the draft. `skills` in `opencode.json` is a plain
  list of folders, which the plugin does not need.
- OpenCode ships its own `build` agent, and the generic role `build` was
  dispatched by its bare name, so in OpenCode a generic `build` task went to
  OpenCode's agent. And no generic agent was registered at all, so every
  other generic role pointed at an agent that did not exist.

So the package:

- is `@vitruviansoftware/opencode-vitruvian-orchestrator`, exports `./server`
  and `./tui`, and lists what it ships in `files`;
- registers the ten generic agents as `vitruvian-orchestrator:<role>` and the
  two skills by name, keeping any agent or skill the user or repository
  already defines (`lib/register.mjs`); and the team tool's `dispatch` for a
  generic role in OpenCode is now `vitruvian-orchestrator:<role>`, the same
  form as Claude Code;
- is released by release-please (`release-type: node`, component
  `vitruvian-orchestrator-opencode`) and exported to the
  `vitruvian-orchestrator-opencode` mirror, whose `release.yml` publishes each
  new version to npm with trusted publishing and tags it.

A new package name cannot have a trusted publisher until it exists. So James
publishes the first version once, by hand, from a clone of the mirror (npm
needs his 2FA); until then the mirror's publish step warns and skips. Then a
`tools/registry-trust/bootstrap.tsv` row and `registry-trust:setup` hand every
later release to CI. The website catalog lists the package once it is on npm.

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
