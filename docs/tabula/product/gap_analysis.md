# Gap Analysis: Workona vs. Tabula

> **Version 3 (release-prep), 2026-06-14.** This document supersedes the earlier structural-parity
> gap analysis. Method: Workona's first-party help documentation + a fan-out web research pass with
> adversarial verification, then a **live hands-on audit** of the Workona web app (paid account) and
> confirmed third-party pricing. Tabula side is ground truth from this repo.
>
> Related references: [`workona_walkthrough.md`](./workona_walkthrough.md),
> [`../architecture/workona_research.md`](../architecture/workona_research.md),
> [`ui-design-language.md`](./ui-design-language.md), [`REQUIREMENTS.md`](./REQUIREMENTS.md).

## Why this rewrite

The previous version measured **structural parity** ("do we have Spaces, Resources, Sections,
Search?") and concluded most gaps were closed. That is accurate but measures the wrong axis.
Workona's UX advantage was never its data model — which Tabula has cloned with high fidelity, down to
the `#3370ff` blue. Its moat is the **connected layer** (live integrations, cross-surface search,
collaboration, a Teams tier, template automation) and the **depth** of Notes/Tasks. This document
scores those axes and frames the result for an upcoming release.

## 1. Executive summary (release lens)

Tabula is ready to ship as what it actually is: a fast, private, **local-first** tab-and-workspace
organizer with a more generous free tier — at genuine parity with Workona's *organizer shell* and
ahead on offline, privacy, visual polish, and price. It is **not** ready to position as a "Workona
replacement," because Workona's stickiness comes from a **connected workspace** (live
Google/GitHub/Confluence/Slack integrations, cross-surface search, real-time collaboration, a Teams
tier, and a template-automation engine) that Tabula has not built yet.

Release strategy follows directly: **lead with the wedge, do not over-claim the gap.**

## 2. Pricing & positioning

| Tier           | Workona                                                                         | Tabula (planned)                              | Tabula edge            |
| -------------- | ------------------------------------------------------------------------------- | --------------------------------------------- | ---------------------- |
| **Free**       | 5 spaces, limited                                                               | 10 workspaces, 30-day backups                 | 2× the free tier       |
| **Pro**        | $6/mo billed annually ($72/yr) / $8/mo monthly; 1 user; unlimited; 90-day; integrations; templates | $4.99/mo, unlimited, 90-day backups | ~17–38% cheaper        |
| **Team**       | ~$7–9/user/mo (min 3, up to 25); shared spaces; admin                           | $6.99/user/mo; shared; SSO; SCIM; admin       | Comparable / under     |
| **Enterprise** | Contact sales (SSO, SCIM, domain restrictions)                                  | folded into Team / future                     | —                      |

**The wedge, in one line:** *"Twice the free workspaces, lower Pro price, fully offline, and your
tabs never leave your machine."* A defensible, true position against a paid-leaning incumbent that
sidesteps the connected-layer gaps entirely.

> Pricing confidence: aggregated from third-party trackers (SaaSworthy, G2, Capterra, TrustRadius,
> Efficient.app) plus Workona's help center; not read from a live billing page. Sources show a $6–9
> spread on Pro; **Free = 5 spaces** is consistent across sources.

## 3. Terminology reconciliation

The two products reuse the same words for different things. Read this before the scorecard.

| Concept                                   | Workona                          | Tabula                       |
| ----------------------------------------- | -------------------------------- | ---------------------------- |
| Account/org container                     | **Workspace** (account-level)    | *(none)*                     |
| Shared-space container (team tier)        | **Team** (sidebar team section, admin/member roles) | *(none — Phase 4)* |
| Per-project container                     | **Space**                        | **Workspace** / **Space**    |
| Sidebar grouping of projects              | **Section**                      | **Section / Group**          |
| Saved links in a project                  | **Resource**                     | **Resource**                 |
| Grouping of resources/notes/tasks         | **Section** (overloaded)         | **Section** (overloaded)     |

**Tabula's "Workspace" ≈ Workona's "Space."** Workona has *two* tiers above the Space (account
Workspace + Team); Tabula has none. That missing **Team** tier is the structural prerequisite for
collaboration.

## 4. Dimension scorecard

Parity key: 🟢 Tabula ahead · 🔵 at parity · 🟡 partial gap · 🔴 major gap · ⚪ not started.
★ = confirmed in the live audit.

| #  | Dimension                                  | Workona                                                       | Tabula                                             | Parity |
| -- | ------------------------------------------ | ------------------------------------------------------------ | -------------------------------------------------- | ------ |
| 1  | Core IA (Space/Resource/Notes/Tasks) ★     | Mature                                                        | Faithful clone, verified                           | 🔵     |
| 2  | Sidebar nav + Sections + color accents ★   | Drag-drop, color-coded                                       | Same + richer accent priority                      | 🔵     |
| 3  | Resource management (core) ★               | `+` menu (tab/URL/file/Drive), hover pencil/trash/✈, typed labels | No file upload / no share; favicon + title    | 🟡     |
| 4  | Command palette (local scope) ★            | —                                                            | Cmd+K + type filters + history (local content)     | 🔵     |
| 5  | Tab suspension                             | Dedicated Tab Suspender extension                            | Built-in auto-suspend                              | 🔵     |
| 6  | **Visual design & polish ★**               | Clean but **flat/utilitarian**                               | Glassmorphic + framer-motion + full token system   | 🟢     |
| 7  | Local-first / offline / privacy            | Hybrid web-app shell; weak offline                           | Local-first, 0ms, offline, extension isolation     | 🟢     |
| 8  | Cost & free tier                           | 5 free; Pro $6–8/mo                                          | 10 free; Pro $4.99/mo                              | 🟢     |
| 9  | Notes depth ★                              | Sections, attachments (tabs/URLs/files/Drive), fullscreen, real-time co-edit | Rich-text + markdown, inline edit          | 🟡     |
| 10 | Tasks depth ★                              | Sections, due dates, assignees, multiselect, cross-space "My Tasks" | Checkbox + completion only                  | 🟡     |
| 11 | Verified cross-device sync                 | Unlimited sessions, hourly snapshots, cross-device merge     | Account-level backup; sync `[/]` **unproven E2E**  | 🟡     |
| 12 | Session history depth                      | Per-space, restore-any-point                                | Coarse, account-level                              | 🟡     |
| 13 | Global keyboard shortcuts                  | From any tab (save/switch/search/tasks)                     | Dashboard-scoped only                             | 🟡     |
| 14 | **Split / multi-pane layout ★** *(new)*    | Two content panes side by side (e.g. Notes \| Tabs), toggle  | Single-pane                                        | 🟡     |
| 15 | Multi-window / archive                     | "Open in current window" / hidden-window; archive (Pro)      | Designed (URL-as-state) / archive planned          | 🟡     |
| 16 | **Universal cross-surface search ★**       | Spaces + Drive + GitHub + Confluence + web, ⌥+S from any tab | Cmd+K, **local content only**                      | 🔴     |
| 17 | Sharing & collaboration ★                  | Real-time co-edit, edit/view perms, presence, no-extension access, private tabs | **Placeholder** button; relay designed, uncoded | 🔴     |
| 18 | Onboarding / first-run                     | ~30-min guided setup, manager vs individual paths            | Empty states only; **no first-run**                | 🔴     |
| 19 | **Integrations ★** *(widened)*             | Google Workspace + **GitHub + Confluence** + Slack           | None (Phase 3)                                     | ⚪     |
| 20 | **Cross-app Create palette (⌥+N) ★** *(new)* | Spawn Docs/Sheets/Slides/Drive, GitHub PR/repo/codespace/project/gist, Confluence space/page | None | ⚪ |
| 21 | Teams tier ★                               | Top-level Team container, admin/member roles, admin dashboard | None (Phase 4)                                    | ⚪     |
| 22 | Templates + automations                    | Properties, auto-create (Drive/Docs/Slack/tasks), Zapier 6,000+ apps | None (Phase 3)                             | ⚪     |

### Live-audit notes (this session)

Driving the live Workona app added/widened several findings the docs alone did not surface:

- **Integration breadth is bigger than the docs imply.** Beyond Google Drive + Slack, Workona has
  deep **GitHub** (new PR / repo / codespace / project / gist) and **Confluence** (new space / page)
  integrations, surfaced in *both* Universal Search and the Create palette.
- **Cross-app Create palette (⌥+N)** — a command bar that spawns native objects across Google
  Workspace, GitHub, and Confluence directly into a space. Tabula has no analog.
- **Split / multi-pane space layout** — each space can show two content panes side by side, toggled
  from the top-right. Tabula is single-pane.
- **The per-space "Chat" view is a bound Slack channel.**
- **Richer space context menu** — Open in new window, Duplicate, Save as space template, Add property
  field (template properties), Add description — beyond Tabula's rename/color/move/delete.
- **Visual verdict flips to Tabula's favor.** Workona's live UI is clean but flat and utilitarian;
  Tabula's frosted-glass modals + framer-motion polish are at or above that bar.

## 5. Gap register (prioritized for the release)

| Priority | Gap                                   | Severity      | Tabula status     | Effort   | Recommendation                                        |
| -------- | ------------------------------------- | ------------- | ----------------- | -------- | ----------------------------------------------------- |
| **P0**   | Verified cross-device sync            | 🔴 trust      | `[/]` unproven    | Med      | Prove E2E before claiming sync; underpins history+teams |
| **P0**   | Onboarding / first-run                | 🔴            | none              | Low–Med  | Cheapest high-leverage activation win                 |
| **P1**   | Google Drive integration (MVP)        | 🔴→⚪          | Phase 3           | High     | Unlocks ~80% of the "hub" feel; do before Slack/GitHub |
| **P1**   | Sharing (relay pattern)               | 🔴            | designed, uncoded | Med–High | Viral loop without abandoning local-first             |
| **P1**   | Teams tier                            | ⚪            | Phase 4           | High     | Prerequisite for collaboration; needs the missing top tier |
| **P2**   | Universal / cross-surface search      | 🔴            | local only        | Med      | Extend Cmd+K to live tabs → Drive; add global shortcut |
| **P2**   | Notes depth (sections, attachments)   | 🟡            | basic             | Med      | Sections + attachments first; co-edit rides on sync   |
| **P2**   | Tasks depth (My Tasks, due, assignee) | 🟡            | basic             | Med      | Cross-space "My Tasks" hub is the headline miss       |
| **P2**   | Split / multi-pane layout             | 🟡            | single-pane       | Med      | Optional; raises information density                  |
| **P3**   | Cross-app Create palette              | ⚪            | none              | High     | Depends on integrations landing first                 |
| **P3**   | Templates + automations               | ⚪            | Phase 3           | High     | Defer; depends on integrations                        |
| **P3**   | Archive, file upload, ✈ share, New Tab page | 🟡      | partial           | Low      | Quick parity round-out                                |
| **P3**   | Multi-window spaces                    | 🟡            | designed          | Med      | Phase 2 as planned                                    |

## 6. Recommended release scope

**Ship & market now (true, defensible):**

- The organizer core — Spaces/Sections/Resources/Notes/Tasks, drag-and-drop, color accents, Cmd+K
  **local** search, tab suspension, glassmorphic polish.
- The wedge — local-first, offline, private, 10 free workspaces, $4.99 Pro.

**Release-blocking decisions (tracked as issues):**

- **Sync messaging** — do not advertise "cross-device sync" until P0 E2E verification passes. If not
  ready, ship single-device and frame sync as "coming." Shipping unproven sync is the biggest
  reputational risk.
- **The Share button** — currently a placeholder. For v1, either ship the documented relay flow or
  hide the button. A dead Share button reads as broken.
- **Onboarding** — cheapest high-leverage add before launch; even a 3-step first-run materially lifts
  activation.

**Explicitly defer & do not over-claim:** integrations (Drive/GitHub/Confluence/Slack), universal
cross-surface search, real-time collaboration, Teams, templates/automations, the cross-app Create
palette, split layouts.

**Positioning guardrail:** market Tabula as *"the private, local-first workspace organizer,"* **not**
*"a Workona alternative."* The moment a head-to-head is invited, the connected-layer gap (rows 16–22)
becomes the story. Lead with offline + privacy + price, where Tabula wins outright.

## 7. Where Tabula already wins (protect these)

Local-first offline (0ms, works on a plane) · privacy/isolation (extension context) · cost & free
tier (2× free workspaces, lower Pro price) · visual polish (live-confirmed at/above parity). The
strategic tension is unchanged: the local-first architecture that wins these rows is what makes the
connected-layer rows hard — every gap-closing move must pass "does this break offline/privacy?", and
the **relay pattern** is the template for doing it right.

## 8. Caveats & confidence

- Workona findings are first-party-verified plus one live hands-on audit (read-only; the audited
  account's layout was restored, billing untouched).
- Pricing is third-party-aggregated, not from a billing page; the $6–9 Pro spread reflects
  source variation.
- Tabula `[/]` items (sync, conflict resolution, tab save/restore/suspend) are coded-but-not-verified
  per [`REQUIREMENTS.md`](./REQUIREMENTS.md) and rated partial, not done.
- "Tab management off by default" for Workona is inferred from its onboarding (optional step 3).

## 9. Sources

- Live audit (2026-06-14 session).
- Workona help: [how-to-use](https://workona.com/help/how-to-use-workona/),
  [spaces](https://workona.com/help/spaces/), [resources](https://workona.com/help/resources/),
  [notes](https://workona.com/help/notes/), [tasks](https://workona.com/help/tasks/),
  [collaborate](https://workona.com/help/collaborate/), [teams](https://workona.com/help/teams/),
  [space-templates](https://workona.com/help/space-templates/),
  [shortcuts](https://workona.com/help/shortcuts/), [extensions](https://workona.com/help/extensions/),
  [tab-manager](https://workona.com/help/tab-manager/).
- Pricing: [SaaSworthy](https://www.saasworthy.com/product/workona/pricing),
  [G2](https://www.g2.com/products/workona/reviews),
  [Capterra](https://www.capterra.com/p/197971/Workona/pricing/),
  [TrustRadius](https://www.trustradius.com/products/workona/pricing),
  [Efficient.app](https://efficient.app/apps/workona).
- Tabula repo docs (README, REQUIREMENTS.md, ui-design-language.md, user-journey-walkthroughs.md,
  workona_research.md, global.css).
