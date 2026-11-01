# Coverage ledger: how we know the spec isn't missing anything

**Result:** every checklist item the app itself provides is accounted for in spec files 01–03. That includes the 18 behaviours found by the final UI-text check, which have been merged into their sections. Each is marked "(added from the UI-text check)".

"Accounted for" doesn't mean "seen working". The confidence of each item is in the spec text (Observed or Inferred), and the known gaps are listed in the [README](README.md#known-gaps-not-yet-covered).

**Courier Milestone 4 implementation status:** Parts 4.1 through 4.7 are complete in Courier (`apps/desktop/courier/docs/m4-acceptance.md`). Every row in [ledger.tsv](ledger.tsv) is either shipped natively on this Mac or documented with its explicit iteration-1 stub / non-applicable rationale in `m4-acceptance.md`.

**Courier Milestone 5 (local API and MCP):** the `setting:integrations` rows are accounted for in `apps/desktop/courier/docs/m5-acceptance.md`: Allow connections, Remote Access, Cursor and VS Code ship; Install to ships in part (Claude Code over HTTP and stdio); Claude Desktop (the `.dxt` extension download) and Raycast (which needs the REST API) are not planned in iteration 1. The reference app's REST API (`/v1`) and its OAuth flow have no ledger rows; they are listed as out of scope in the same file.

## The checklists

The app ships two lists that work as checklists, and the live walk-through gave us four more. Every item on every list was checked against the spec.

| Checklist | Where it comes from | Items | In the spec |
|---|---|---|---|
| Interface components | Component file names left in the shipped bundle | 434 | 434 (all assigned to a feature area in 01) |
| Command-bar commands | Live: every entry in ⌘J, excluding contacts and settings mirrors | 74 | 74 |
| Hotkeys | Live: Settings → Hotkeys, every row | 57 | 57 |
| Settings | Live: every toggle and select in 9 panes. Accounts, Devices and Storage are skipped because they show personal data. | 87 | 87 |
| Menu items | Live: the app's own menu-bar menus (Beeper, File, View, Help) | 28 | 28 |
| UI text | The app's English text catalogue (strings over 3 characters) | 2,631 | 2,631 accounted for (breakdown below) |

The per-item results for the first five lists are in [ledger.tsv](ledger.tsv): anchor, item, which spec files mention it, and status. All rows are `covered`.

### UI text breakdown

A string doesn't need to appear word for word in the spec; describing the behaviour counts. So the text check ran in two steps:

1. **1,177** strings appeared word for word in files 01–03.
2. The other **1,454** were each classified by hand into one bucket:

| Bucket | Count | Meaning |
|---|---|---|
| Paraphrased | 772 | The behaviour is described in the spec in other words |
| Detail | 520 | A small message (error, toast, confirmation, tooltip, plural form) for a feature already in the spec |
| Noise | 77 | Units, weekday names, alt text, generic words |
| **Gap** | **85** | Behaviour the spec didn't describe at first. Grouped into **18 features**, now merged into 01–03 (search for "added from the UI-text check"). |

1,177 + 772 + 520 + 77 + 85 = 2,631. Nothing is unclassified.

## Borderline classifications

- **"Social Account"** and **"Some of your accounts are still on Beeper’s Cloud"** appear only in
  the translation table. We found no code that uses them, so we marked them DETAIL with a note. They
  may belong to a feature that is turned off or was removed.
- **"Last sent message"** is defined as a search section name, next to "Last archived". The search
  code never lists it, so we marked it DETAIL rather than GAP.
- **"thread archived", "notification clicked", "message scheduled"** are labels for local usage
  counters in the dev-only usage stats view. We marked them NOISE.
- **X login passcode errors** (for example "Passcode isn't set up for X Chat") suggest the X login
  also asks for the X Chat passcode. The spec already lists "passcode locked" among the login
  errors, so we marked them DETAIL. If the passcode is a separate login step, it would belong in
  03 §1.3 for X.

## What this method can't catch

The checklists only cover what the app ships to your Mac. They can't see:
- **Server-driven content:** cloud-only login steps, flag values, plan limits and AI responses.
- **Behaviour without text:** animations, timings, drag-and-drop feel, and exactly how the layout responds to window size. These need the live visual pass on a test account (see README).
- **Hard-coded English the app doesn't translate:** the native right-click menu, for example. File 02 lists these where they were found.

## Regenerating the ledger

The scripts and raw captures live outside the repo, because they include a copy of Beeper's text catalogue and screenshots of real chats. To regenerate against a newer Beeper version:

1. Unpack `app.asar` from the installed app.
2. Pull the component names and the English keys of a translation table out of the renderer bundle.
3. Relaunch Beeper with `--remote-debugging-port` bound to 127.0.0.1. Capture the settings panes, ⌘J, the Hotkeys pane, and the menu bar (through System Events).
4. Check each item against files 01–03. Anything not found goes back through the classification step.

If the generator gets reused for more than one version, promote it to a proper tool in the repo rather than a scratch script.
