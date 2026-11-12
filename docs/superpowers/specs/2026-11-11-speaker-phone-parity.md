---
status: completed
---

# Vitruvian Speaker on the phone: every extension option, and no drift

## The problem

The Vitruvian extension and the Android Remote phone app configure the same Vitruvian Speaker. Since the
one-rulebook work (#4527, #4534, #4544, #4557, #4565), the *wording, choices and limits* of each
setting come from one catalog (`SettingsCatalog.swift`), sent to the phone in `--state` →
`settings[]`. But *which* settings and actions the phone offers is still hand-wired at two layers:

- **The Mac helper** (`macagent/rs/src/speaker.rs`) has one hand-written update field per
  setting, and one per action. Its "every catalog setting maps" test uses a hand-kept list, so the
  two chat **Address** settings slipped through, with no failing test.
- **The phone** draws a row only for the keys it names. A new catalog setting arrives in
  `settings[]` and is silently not shown.
- **Actions** (sign in, door switch, remove speaker, hooks, secrets…) are hand-mapped at every
  layer, with no shared list at all.

An audit on 2026-11-11 found 63 extension controls, of which 54 worked from the phone.

## The strategy: generic for settings, a checked manifest for actions

1. **Settings need no per-setting code.**
   - **Helper.** Any `{key, value}` whose key is in the catalog is forwarded as
     `--apply {"op":"set","key":…,"value":…}`. Vitruvian Speaker validates it against the catalog, so the
     helper does not re-validate.
   - **Phone.** Any catalog setting the phone has not placed in a hand-designed section is drawn by
     a generic renderer from its catalog entry (kind, label, choices, limits, `shown`), in an
     "Other settings" group. A new setting appears on the phone the day Vitruvian Speaker ships it, with
     no phone or helper release.
   - **Tests.** These are derived from the golden fixture, not hand lists:
     - The Rust test asserts that every key in `state_v1.json` `settings[]` can be set.
     - The Kotlin test asserts that every key in the golden payload renders exactly one row,
       placed or generic.

2. **Actions are listed once, in a checked-in manifest.**
   - **The manifest.** `apps/desktop/vitruvian-speaker/testdata/controls.json` names every non-catalog
     control the extension offers. For each it records the `--apply` op or CLI flag, and what the
     phone does with it:
     - `"phone": "supported"`, or
     - `"phone": "excluded"` with a one-line `reason`.
   - **Swift test.** Every op in `VitruvianSpeakerStateContract.supportedOperations` appears in the
     manifest. Adding an op without saying what the phone does fails CI.
   - **Rust test.** Every manifest entry marked supported is mapped by the helper.
   - **Kotlin test.** Every manifest entry marked supported has a phone control. The test finds it
     by its manifest id, which the phone code carries as a constant.

3. **Visibility follows the catalog's `shown` rule.** The phone adds no extra hide rules of its
   own. Sections the extension shows while Broadcasting is off stay visible on the phone too.

```
SettingsCatalog.swift ──► --state settings[] ──► helper (generic set) ──► phone (generic rows)
controls.json ─────────► Swift test (every op listed) / Rust test (supported mapped) / Kotlin test (supported drawn)
```

## Gaps closed by this change

- The Beeper and Courier **Address** settings. The generic set and generic rows cover them.
- **Picking a different Google Home.** `--state` today lists only the saved home.
- **Removing any speaker**, not only the default.
- **The door switch's "Copy settings from…".** The helper never sent `copy`.
- **A stale coding-agent hook offers Remove.** The helper passes `stale_command` and
  `hook_program`.
- **Coding-agent and chat-app sections stay visible** while Broadcasting is off, as in the
  extension.
- **The chat monitor Start/Stop** is shown only when the extension shows it.

## Deliberately excluded (recorded in the manifest)

- **Door housekeeping:** quitting the other copy, turning off its login item, and moving it to the
  Trash. These act on another app's process and files on the Mac. A Trash from a phone is
  destructive and hard to undo.
- **Files rows:** settings, secrets and history paths are Mac file paths, meaningless on a phone.
- **Extension-only navigation:** section picker, "More settings…", console link.

## Not in scope

- The phone-only extras: Reset, "Test from your phone", notification mirror, and the volume
  stepper.
