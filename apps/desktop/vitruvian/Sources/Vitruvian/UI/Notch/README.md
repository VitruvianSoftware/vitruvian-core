# Notch

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Sources/Vitruvian/UI/Notch`.

## Interface
- `[AgentsSlotPlace.swift:AgentsSlotPlace]`
- `[NotchMascotView.swift:NotchMascotView]`
- `[NotchMascotView.swift:NotchMascotTrackView]`
- `[NotchMascotView.swift:NotchMascotActivityVisit]`
- `[NotchMusicView.swift:NotchMusicIdleTransport]`
- `[NotchNotificationsView.swift:NotchClearNotificationsButton]`
- `[NotchView.swift:NotchClearCapturesButton]`
- `[NotchView.swift:NotchRestingBattery]`

## Invariants
- None

## Side Effects
- [NotchClipboardView.swift:19]: `@State private var query = ""`
- [NotchClipboardView.swift:50]: `history.filteredEntries(matching: query).filter { !pinnedOnly || $0.isPinned }`
- [NotchClipboardView.swift:54]: `private var canReorder: Bool { query.trimmingCharacters(in: .whitespacesAndNe...`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Sources/Vitruvian/UI/Notch/...`
