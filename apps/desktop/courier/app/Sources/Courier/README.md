# Courier

## Overview
Component package providing implementation for `apps/desktop/courier/app/Sources/Courier`.

## Interface
- `[AIPane.swift:AIPane]`
- `[AIPane.swift:AIPaneHeader]`
- `[AIPane.swift:MessageTranslationRowView]`
- `[AISettingsPane.swift:SettingsWindowDetectionObserver]`
- `[AISettingsPane.swift:AISettingsPane]`
- `[AboutSettingsPane.swift:AboutSettingsPane]`
- `[AboutSettingsPane.swift:UpdatesSection]`
- `[AccountBanner.swift:AccountBannerView]`
- `[AccountBanner.swift:AccountStatusStrip]`
- `[AccountsSettingsPane.swift:AccountsSettingsPane]`
- `[AccountsSettingsPane.swift:RemoveAccountConfirmationSheet]`
- `[AddNetworkView.swift:AddNetworkView]`
- `[App.swift:CourierApp]`
- `[AppDelegate.swift:AppDelegate]`
- `[AppIconPickerView.swift:AppIconPickerView]`
- `[AppLockOverlay.swift:LockableWindowContent]`
- `[AppLockOverlay.swift:AppLockOverlay]`
- `[AttachmentCarouselOverlay.swift:AttachmentCarouselOverlay]`
- `[AttachmentChip.swift:FileSize]`
- `[AttachmentChip.swift:SystemQuickLookPanelController]`

## Invariants
- None

## Side Effects
- [ChatInfoPane.swift:17]: `///     Pinned, Shared Media (3×3 grid), Files, Links, Bookmarks (`search.que...`
- [CommandBarOverlay.swift:88]: `if model.query.isEmpty, !model.breadcrumb.isEmpty || model.mode == .recentCha...`
- [CommandBarOverlay.swift:145]: `text: $model.query,`
- [CommandBarOverlay.swift:157]: `if !model.query.isEmpty {`
- [ConversationView.swift:222]: `onSearch: { query in`
- [ConversationView.swift:225]: `query: query,`
- [ConversationView.swift:240]: `query: "",`
- [EditGroupSheet.swift:242]: `/// Sheet for inviting contacts or people from shared groups (`people.contact...`
- [EditGroupSheet.swift:288]: `self.onSearch = { query in _ = onSearch?(query) }`
- [EditSpacesWindow.swift:45]: `let query = search.trimmingCharacters(in: .whitespaces)`

## Verification
- Run: `bazel test //apps/desktop/courier/app/Sources/Courier/...`
