# Multi-OS strategy

* **Status:** decided, 2026-11-15: stay macOS-only and keep tracking upstream
* **Author:** James Nguyen, with Claude
* **Brainstorm date:** 2026-11-12, reviewed by six independent reviewers

## Decision

Vitruvian Atrium stays a macOS app. It stays a GPL-3.0 fork that keeps taking
upstream's fixes. We are not building a shared Rust core, a Flutter app, a
Linux or Windows app, or a Mac App Store version now.

**Why:**

- **Keeping upstream's fixes is worth more than a rewrite.** About 92% of the
  code is upstream's, and upstream ships fixes most days. The weekly sync works
  again since 2026-11-12, and batches 33 to 42 landed on 2026-11-13 (470
  upstream commits ported, 123 skipped, 2 pending in `upstream/ledger.tsv` on
  2026-11-15). Each service moved to a Rust core would stop taking those fixes
  or need every fix translated by hand.
- **The rewrite would buy little on Linux.** The largest features (the notch
  island, window snapping, the switcher, Dock previews, fan control) can't run
  as a normal app on GNOME under Wayland, and free Linux tools already cover
  several others.
- **Nobody has decided yet what a buyer pays for.** Upstream is free and its
  source is public, and a rewrite doesn't change the GPL. Revenue work starts
  with that answer, not with architecture.
- **The Mac App Store is out for good.** The GPL forbids it, and so do the
  private macOS interfaces and the sandbox.

**What would reopen this:**

- upstream stops shipping, or the fork stops tracking it;
- a revenue model is chosen that needs other platforms;
- real demand from Linux users.

If one of these happens, start from the staging below: decisions first, then a
feature audit. The smallest Linux step is a small app for AI agent usage
tracking, not a port.

The rest of this page is the brainstorm brief as it stood on 2026-11-12, kept
as the record of what was weighed.

## Overview


Atrium is a macOS menu-bar utility hub: a volume mixer, system monitor, app switcher, window
snapping, Dock previews, clipboard history, a notch island, screen recording, AI agent usage
tracking and a command bar, each of which can be switched on or off. It is a GPL-3.0 fork of
the free vorssaint-utils and is sold, or will be, as a direct download.

The goal is revenue first, and second, sharing Atrium with Linux users.

The working idea was this. Keep the Mac app in SwiftUI. Move the shareable logic and screen
state into a Rust core one service at a time. Then add a GNOME app (GTK4 + libadwaita) and
later a Windows app (WinUI 3), both on the same core.

Six fresh-context reviewers read the code and rejected the idea as written. Their reason: it
puts a large rewrite ahead of two decisions it depends on. Those are what a buyer pays for,
and whether the fork keeps taking upstream's fixes.

## Analysis

### Facts this rests on

These were checked in the code unless marked.

- **The code is almost all upstream's.** 722 of 861 Swift files, about 324,000 of 351,000
  lines, carry Vorssaint's GPL header. Upstream has many contributors, so it cannot be
  relicensed. A Rust port of that code is still GPL.
- **The Mac App Store is out.** The licence forbids it. So do the private macOS interfaces
  the app uses (MediaRemote, CGS/SkyLight, AppleSMC, TCC), and the sandbox would block window
  control and the fan helper.
- **Upstream moves fast.** The upstream ledger has about 480 entries since the 2026-10-02
  import.
- **There are no view models.** The word "ViewModel" appears nowhere. UI files reach into
  service singletons (`.shared`) 1,338 times, and views read and write settings directly
  about 885 times. The 885 is the reviewers' count; I didn't check it.
- **Features are built in, not installed separately.** They are all compiled into one app
  and switched on or off through `Core/FeatureCatalog.swift`.
- **There is already a seam to other OSes.** Migrated tools reach the system only through a
  capability broker, `Services/Platform/Broker/`. Outside tools speak the MIT-licensed
  Vitruvian tool protocol, and the app draws their UI from a block tree.
- **The build tools are partly ready.**
  - What exists: rules_rust and rules_swift. Courier already links a Rust static library
    into a Mac app.
  - What's missing: UniFFI, a Windows Rust target and a Windows runner.
  - What's too old: the default Rust is 1.75. The 1.98.1 toolchain exists only behind a
    transition.
- **Assumed, not checked:** on GNOME/Wayland, a normal app can't move other apps' windows,
  draw overlays or reliably grab global hotkeys. GNOME has no tray by default.

### Objections, most severe first

1. **No view models exist to move.** Step 1 is really "invent view models in Swift, then move
   them". That is a big refactor of the files upstream changes most.
2. **Each service moved to Rust stops taking upstream fixes.** The porting tool merges Swift
   into Swift. A Rust service either gets every upstream fix rewritten by hand or stops
   tracking upstream. The plan didn't pick, and the cost grows with every service moved.
3. **Nobody has said what a buyer pays for.** Upstream is free, the source of every release
   is public, and anyone can legally remove a licence check from GPL code. A rewrite opens
   no licensing door. Each revenue model needs different build work.
4. **Settings would have two owners.** If Rust owns "what's enabled" while Swift views still
   read and write the settings store directly, the two drift apart silently.
5. **There is no rollback and no proof that the Rust code matches.** The beta channel
   publishes on every push. Each slice needs the Swift path kept behind a switch, plus a
   test that runs both versions on the same inputs and compares the results.
6. **Most of the large features can't run on GNOME/Wayland.** That covers the notch, window
   snapping, the switcher, Dock previews and fan control. Linux already has free tools for
   several others: Pop Shell, GPaste, PipeWire mixers, Resources and Kooha. Overlays would
   have to be GNOME Shell extensions, which are written in JavaScript, so the Rust core
   wouldn't help with them.
7. **Little of the code can genuinely be shared.** AI agent usage tracking is the clear best
   candidate: plain parsers, and the logs sit in the same home-folder paths on Linux. After
   that come pricing, command-bar ranking, the feature catalog and metric formatting.
8. **Live updates across the Rust boundary need a threading rule.** Swift 6 stops the app
   when UI code runs off the main thread. The safe pattern, which `ToolPanelHost` already
   uses, is for Rust to bump a revision number and the UI to pull a snapshot at most once a
   frame.
9. **The licence limits where the code can live.** A ported core is GPL, and so is every
   app that links it. It must sit in the GPL subtree, not in the Apache monorepo. A core
   written from scratch could choose its own licence.
10. **The translations aren't portable.** About 90 `*Strings.swift` files cover 15
    languages. They would have to be copied into each OS or moved to one shared format.
11. **Windows is premature.** There is no evidence anyone wants it, and its Rust-to-C#
    binding tool is third-party.

## Goals vs. Non-Goals

* **In-scope goals**
  * Earn revenue from Atrium.
  * Ship something useful to Linux users.
  * Keep the native look on each OS.
  * Keep OS-only features optional.
* **Out-of-scope non-goals**
  * The Mac App Store, permanently, for the reasons above.
  * Windows until a Linux app has shipped and held steady.
  * A one-shot rewrite of the Mac app.

## Alternatives Weighed

- **Flutter/Dart for every OS:** rejected.
  - It draws imitation controls and has no real system glass.
  - Its multi-window support is weak, and Atrium is mostly small windows.
  - Each OS still needs native code for overlays and system access.
  - Rewriting in another language doesn't remove the GPL.
- **A clean-room rewrite for the App Store:** rejected. It means rewriting about 92% of the
  code, and the private-interface and sandbox problems would remain.
- **Tauri:** noted as the fallback if a single shared UI ever becomes the goal. It handles
  many windows and uses less memory than Flutter.
- **The reviewers' alternatives, still open:**
  - **A. Test revenue first, with no architecture work.** Finish Developer ID signing and
    notarization, then sell supported builds with updates.
  - **B. Paid add-ons through the MIT tool protocol.** For example a "pro" agent-usage tool
    or a hosted link service, kept outside the GPL app.
  - **C. A small Linux app written from scratch.** Agent usage first, perhaps with a GNOME
    Shell extension. It would carry its own licence if written from public format docs
    rather than upstream's code. That is a legal call.
  - **D. Use the tool protocol as the cross-platform layer.** Each OS implements the broker
    and draws the block tree, with no UniFFI and no C# binding tool.
  - **E. Share logic only, never view models.** Move code only when two apps actually need
    it.
  - **F. Share data, not code.** All apps read the same price list, catalog and settings
    schema.

## Key Decisions & Staging for Next Steps

**Decisions still to make:**
1. What does a buyer get that free upstream doesn't? Do Linux users pay, or is Linux the
   free half?
2. Does the fork keep tracking upstream for good? For services rewritten in Rust, are they
   frozen or do they get every fix translated by hand?
3. Which Linux target: GNOME only or KDE too, which distros, and Flathub or a self-hosted
   Flatpak?
4. Port upstream code (it stays GPL) or write a clean-room core (it can carry its own
   licence)?
5. Rust core through UniFFI, or the existing tool protocol as the shared layer?
6. Is Developer ID signing and notarization fully done? The README says releases aren't
   notarized, and UPSTREAM.md says 3.51.0 was signed.

**Staging the reviewers suggest:**
0. **Decide** the points above, and finish signing and notarization. Every revenue model
   needs that.
1. **Audit features** in one table covering every feature:
   - can it be shared, or is it tied to one OS;
   - how often upstream changes it;
   - can GNOME support it;
   - what is it worth in revenue.
2. **Link spike.** Call one trivial Rust function from the Mac app. It must build for both
   Mac CPUs and sign and notarize unchanged.
3. **One slice end to end.** Agent usage parsing and pricing move to Rust, behind a switch
   with a compare-both-versions test. Ship the same code in a minimal GNOME app.
4. **Grow by demand.** Move logic only when Linux needs it, and record each move in the
   upstream ledger.
5. **Windows**, maybe, once the core's interface has held steady.
