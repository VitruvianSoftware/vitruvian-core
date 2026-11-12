# Courierviewtests

## Overview
Component package providing implementation for `apps/desktop/courier/app/Tests/CourierViewTests`.

## Interface
- `[Fixtures.swift:Fixture]`
- `[HeaderLineWindowTests.swift:HeaderLineWindowTests]`
- `[IntegrationsSnapshotTests.swift:IntegrationsSnapshotTests]`
- `[LiquidGlassSnapshotTests.swift:LiquidGlassSnapshotTests]`
- `[MenuEffectTests.swift:MenuEffectTests]`
- `[MessageActionBarPlacementTests.swift:MessageActionBarPlacementTests]`
- `[MessageActionBarPlacementTests.swift:ReactionCardPlacementTests]`
- `[MessageActionBarSnapshotTests.swift:MessageActionBarSnapshotTests]`
- `[MessageSelectionClickTests.swift:MessageSelectionClickTests]`
- `[RowLayeringTests.swift:RowLayeringTests]`
- `[SeedScenario.swift:SeedScenario]`
- `[SeedScenarioSnapshotTests.swift:SeedScenarioSnapshotTests]`
- `[Snapshot.swift:Snapshot]`
- `[Snapshot.swift:SnapshotError]`
- `[UpdatesSnapshotTests.swift:UpdatesSnapshotTests]`
- `[ViewSnapshotTests.swift:ViewSnapshotTests]`
- `[ViewSnapshotTests.swift:SnapshotLoginItemService]`
- `[ViewSnapshotTests.swift:SnapshotBiometricService]`
- `[ViewSnapshotTests.swift:SnapshotMessageSender]`
- `[WindowLayoutTests.swift:WindowLayoutTests]`

## Invariants
- None

## Side Effects
- [MenuEffectTests.swift:143]: `XCTAssertTrue(delegate.inbox.query.filters.contains(.unread))`
- [MenuEffectTests.swift:145]: `XCTAssertTrue(delegate.inbox.query.filters.contains(.drafts))`
- [MenuEffectTests.swift:147]: `XCTAssertTrue(delegate.inbox.query.filters.isEmpty)`

## Verification
- Run: `bazel test //apps/desktop/courier/app/Tests/CourierViewTests/...`
