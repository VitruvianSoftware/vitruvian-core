# Vitruvian brand standard

> **Status:** Draft, 2026-11-10. Names marked *proposed* wait for James's approval.
> **Owner:** James. **Applies to:** every product, repo, doc and agent in `vitruvian-core`.

## 1. The short version

Every product we ship is called **Vitruvian _Noun_**, where the noun says plainly what
it does. One company name, one pattern, no clever words to decode.

- **Vitruvian Software** is the company. It appears in legal text, the site footer,
  signing identities and the GitHub org. Products never say "by Vitruvian Software" in
  their name.
- **Vitruvian Desktop** is the platform. It hosts products as extensions. Inside
  Desktop, a product drops the prefix and shows only its noun ("Code", "Speaker"),
  because the user is already inside Vitruvian.
- **Products** are `Vitruvian <Noun>` everywhere outside Desktop: app name, menu bar,
  site, catalog, README title, store listing.
- **Internal tools** (homelab, Backstage, God's eye view, the MCP servers we only use
  ourselves, build tooling) get no product brand. They keep plain technical names.

The reason: a small company gets more from one strong name than from many weak ones.
Every product someone meets teaches them the word "Vitruvian", and a new product starts
with the trust the others earned.

## 2. Naming rules

| Where | Rule | Example (Speaker) |
|---|---|---|
| Display name (outside Desktop) | `Vitruvian <Noun>` | Vitruvian Speaker |
| Display name (inside Desktop) | `<Noun>` | Speaker |
| Monorepo directory | `vitruvian-<noun>` under its category | `apps/desktop/vitruvian-speaker` |
| Mirror repo | same as the directory | `VitruvianSoftware/vitruvian-speaker` |
| CLI command | `vitruvian-<noun>` | `vitruvian-speaker` |
| macOS / Android bundle ID | `com.vitruviansoftware.<noun>` | `com.vitruviansoftware.speaker` |
| Swift module / type prefix | `Vitruvian<Noun>` | `VitruvianSpeakerCore` |
| MCP server name | `vitruvian-<noun>` | `vitruvian-speaker` |
| release-please component | the directory name | `vitruvian-speaker` |
| On-disk folders | `Vitruvian <Noun>` | `~/Library/Application Support/Vitruvian Speaker` |
| Env vars | `VITRUVIAN_<NOUN>_*` | `VITRUVIAN_SPEAKER_TARGET` |

Choosing the noun:

- **Say the job.** A stranger should guess what it does from the name alone.
- **One word**, a real English noun. No camel-case compounds (`HomeSpeaker`), no
  invented words.
- **No clash** with a well-known developer product in the same space.

Old names are **retired, not aliased**. Once a product is renamed, its old command,
folder and ID are gone. A repo check (see section 6) fails if a retired name comes back,
so a missed caller shows up as a red build instead of a silent fallback.

## 3. Name map

| Today | New name | Status |
|---|---|---|
| Vitruvian Software | Vitruvian Software | company, unchanged |
| Vitruvian (macOS app, shows as "Vitruvian" today) | Vitruvian Desktop | *proposed*; display name only, directory and bundle ID stay `vitruvian` (the platform owns the bare word) |
| Nexus Agent | **Vitruvian Code** | approved |
| HomeSpeaker | **Vitruvian Speaker** | approved |
| Courier | **Vitruvian Courier** | approved |
| Vitruvian Remote (Android) | Vitruvian Remote | already compliant |
| Tabula | Vitruvian Tabs | *proposed* |
| Wand | Vitruvian Wand | *proposed* (already a plain noun) |
| Relay | Vitruvian Relay | *proposed* (already a plain noun) |
| devx | Vitruvian Dev | *proposed*; see open question 1 |
| ESP32-S3 desk companion | Vitruvian Desk | *proposed* |
| GitHub tool, TV tool | GitHub, TV (inside Desktop only) | extensions, already compliant |
| homelab, Backstage, God's eye view, mcp-slack, mcp-roborock, ostation, Wear OS faces | unchanged | internal, no brand |

## 4. What a rename changes

A rename is **everything with the name in it**, not just labels. For an installed app
that includes hidden identifiers, and changing those has consequences the user feels:

| Changes | What the user notices | How we handle it |
|---|---|---|
| Bundle ID | macOS sees a brand-new app | ship the new app; the old one's last release hands over (below) |
| Privacy grants (Accessibility, Screen Recording, Automation …) | asked again | **cannot be migrated** — macOS ties them to the app. A first-run screen explains why and links each setting |
| Application Support / Caches / Logs folders | nothing, if migrated | one-time copy on first launch of the new app, old folder left in place until the copy is verified, then removed |
| UserDefaults domain | nothing, if migrated | import the old domain on first launch |
| Keychain items | nothing, or one sign-in prompt | read under the old service and re-write under the new; if macOS blocks the read, ask the user to sign in once |
| Login item / launchd label | nothing | new app registers its own and unregisters the old |
| Update feed / signed catalog | nothing | the old ID's feed serves one final **bridge release** that installs the new app and quits; the catalog then lists only the new ID |
| CLI command | old command stops working | every caller in this repo and on James's Mac updated in the same change |
| Mirror repo | old URL redirects | GitHub rename; copybara config and Homebrew tap updated together |

**Stored data IDs stay.** Some names live inside users' saved data, not in anything a
person sees: Courier's internal chat server name (`courier.local`, baked into every stored
room, user and media ID), saved config keys like `courier_enabled`, and the Remote app's
wire-protocol keys. Renaming those means rewriting every user's database and breaking
older phones talking to newer Macs, for no visible gain. They stay, and the
retired-names check allows them by exact value.

**Update feeds need a transition.** Old installs look for updates by their old tag
(`courier-v*`, and likewise for the others). The bridge release is published under the
old tag; new releases use the new tag after that.

What we do **not** rewrite: git history, published release tags and changelogs, and
planning docs marked `status: completed`. They record what was true then.

## 5. Rollout

One product at a time, each through the full team (implement → QA → UAT) and landed
before the next starts. The first product is the pilot: its migration code becomes the
shared helper the others reuse, so the hard parts are solved once.

1. This standard and the retired-names check.
2. Pilot: **Vitruvian Code** — fewest hidden IDs, so the helper is built on the easy case
   ([design](../superpowers/specs/2026-11-10-vitruvian-code-rename-design.md)).
3. **Vitruvian Courier** — the largest data store and saved AI/Telegram keychain items.
4. **Vitruvian Speaker** last — its callers include scripts and skills outside this repo
   (`~/bin/speaker-broadcast`, skills under `~/.claude` and `~/.agents`), shared files in
   `~/.gemini`, and the Remote app's Mac helper, which is being changed right now.
5. Docs, diagrams, site and catalog sweep.
6. Mirror repo renames (after the code that names them has landed).
7. Proposed names, once approved.

## 6. Keeping it consistent

- `tools/lint-naming` gains a **retired-names list**. The check fails on any retired name
  outside the allowed places (changelogs, git-history docs, the migration code that has
  to know the old IDs, and this file).
- New products follow section 2 from their first commit.

## 7. Open questions

1. **devx command length.** `vitruvian-dev` is long for a command typed many times a day.
   Option: keep the product name "Vitruvian Dev" but allow one short command (`vdev`).
   That is an exception to section 2, so it is James's call.
2. **Two ID namespaces.** Apps use `com.vitruviansoftware.*`; Desktop extensions use
   `dev.vitruvian.*`. They don't collide, but they are inconsistent. Converging them is a
   separate migration and is not part of this one.
