---
status: in-progress
---

# Nexus Agent → Vitruvian Code (pilot rename)

Pilot for the [brand standard](../../standards/brand.md). Everything with the name in
it changes, including hidden IDs. Existing installs migrate themselves; nothing the user
had is lost except privacy grants, which macOS will not carry over.

Why this product goes first: it has the fewest hidden IDs of the three (no keychain, no
app group, no sandbox, no entitlements), so the migration helper gets built on the easiest
case and is then reused for Courier and Speaker.

## New identifiers

| What | Old | New |
|---|---|---|
| Display name | Nexus Agent / NexusAgent | Vitruvian Code (inside Desktop: Code) |
| Directory | `apps/desktop/nexus-agent` | `apps/desktop/vitruvian-code` |
| App bundle / executable | `NexusAgent.app` / `NexusAgent` | `Vitruvian Code.app` / `VitruvianCode` |
| Bundle ID (= defaults domain) | `com.vitruviansoftware.nexusagent` | `com.vitruviansoftware.code` |
| Swift modules | `NexusAgent`, `NexusAgentCore`, `NexusAgentUI`, `NexusAgentToolCore` | `VitruvianCode`, `VitruvianCodeCore`, `VitruvianCodeUI`, `VitruvianCodeToolCore` |
| App Support | `~/Library/Application Support/NexusAgent` | `~/Library/Application Support/Vitruvian Code` |
| Bot home | `~/.config/nexus-agent` | `~/.config/vitruvian-code` |
| launchd label prefix | `nexus-agent.automation.<uuid>` | `com.vitruviansoftware.code.automation.<uuid>` |
| Desktop tool ID | `dev.vitruvian.nexus-agent` | `dev.vitruvian.code` |
| Tool executable | `nexus-agent-tool` | `vitruvian-code-tool` |
| release-please component / tag | `nexus-agent` / `nexus-agent-vX` | `vitruvian-code` / `vitruvian-code-vX` |
| Mirror repo | `VitruvianSoftware/nexus-agent` | `VitruvianSoftware/vitruvian-code` |
| Homebrew cask | `nexus-agent` | `vitruvian-code` (old token renamed in the tap) |
| Antigravity plugin / npm name | `nexus-agent` | `vitruvian-code` |
| Env vars | `NEXUS_AGENT_*` | `VITRUVIAN_CODE_*` |
| CI units | `nexus-agent-macos`, `nexus-agent-src` | `vitruvian-code-macos`, `vitruvian-code-src` |

Stays as is: Vitruvian Desktop's own legacy `nexusAgent*` defaults keys (they are the
input to an older handoff and are read once), and the mirror's existing
`NEXUS_AGENT_REV_ID` trailers in history (copybara must still find the last one; the new
config reads both names).

## Migration on first launch (new app)

Runs once, guarded by a `migratedFromNexusAgent` flag in the new domain. The app is not
sandboxed, so it can read the old app's files and defaults directly.

1. **Settings:** copy every key from the `com.vitruviansoftware.nexusagent` domain that the
   new domain does not already have.
2. **Folders:** copy `Application Support/NexusAgent` and `~/.config/nexus-agent` to the new
   paths (keep file modes; the bot `.env` is 0600). Old folders are left in place; a
   later release removes them.
3. **Automations:** for each `~/Library/LaunchAgents/nexus-agent.automation.*.plist`,
   unload it, write it again under the new label with the new executable path, load
   it, delete the old file.
4. **Privacy grants:** show a one-time sheet listing the permissions the user had given
   Nexus Agent, each with a button to its System Settings pane.
5. Every step is idempotent and logs what it did; a failed step is reported in the sheet
   and retried next launch, never silently skipped.

Desktop side: the host maps an installed `dev.vitruvian.nexus-agent` to `dev.vitruvian.code`
on its next launch: moves `Tools/` and `ToolData/` folders, rewrites `<id>/<pref>` keys,
updates the handoff code to the new ID.

## Reaching existing installs (bridge release)

Old installs update themselves from the latest release of the mirror repo, pick the zip
whose name contains `universal`, and swap `/Applications/NexusAgent.app` in place. The repo
rename keeps working through GitHub's redirect.

So the last release under the old name is a **bridge**: a `NexusAgent.app` whose only job
is to download the current Vitruvian Code, install it to `/Applications/Vitruvian Code.app`,
open it (which runs the migration above) and move itself to the Trash. The Homebrew tap
gets a rename entry so `brew upgrade` follows. The signed catalog lists only
`dev.vitruvian.code`, and the host's ID mapping covers installed extensions.

## Pull requests

1. **Move and rename in code** (no behavior change): directory move, modules, targets,
   CI units, tools that hard-code the path, release-please component, copybara config,
   env vars, display strings. Proof: `bazel build //apps/desktop/vitruvian-code/...`,
   `bazel test //apps/desktop/vitruvian-code/... //apps/desktop/vitruvian/...`, the
   presubmit generator check, and no remaining old name outside the allowed places.
2. **New identity and migration:** bundle ID, folders, launchd labels, tool ID, the
   first-launch migration and the host mapping, with tests that seed an old install in a
   temporary home and check every item arrives.
3. **Distribution:** bridge release, catalog, site data and downloads, donate page,
   Homebrew tap, mirror repo rename.

## Acceptance (what James sees)

- The Mac app, its menu bar item, About box and Dock all say **Vitruvian Code**; inside
  Vitruvian Desktop the extension says **Code**.
- After updating from Nexus Agent, his settings, chosen models, prompt history,
  Telegram bot and scheduled automations are all still there.
- He is asked once, with a clear explanation, to re-grant the macOS permissions.
- The website, catalog and Homebrew list Vitruvian Code; old links still land on it.
- No file in the repo mentions Nexus Agent outside changelogs, history, this spec and
  the migration code.
