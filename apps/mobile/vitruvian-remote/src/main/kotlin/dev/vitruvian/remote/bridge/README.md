# Bridge

## Overview
Component package providing implementation for `apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/bridge`.

## Interface
- `[ApprovalReceiver.kt:ApprovalReceiver]`
- `[BridgeAccessibilityService.kt:BridgeAccessibilityService]`
- `[BridgeAccessibilityService.kt:ScreenTools]`
- `[BridgeHub.kt:BridgePermissions]`
- `[BridgeHub.kt:BridgeHub]`
- `[BridgeNotificationListener.kt:BridgeNotificationListener]`
- `[BridgeNotificationListener.kt:NotificationTools]`
- `[PhoneBridgeService.kt:PhoneBridgeService]`
- `[Tools.kt:PhoneTool]`
- `[Tools.kt:ToolRegistry]`
- `[Tools.kt:tool]`
- `[Tools.kt:PhoneTools]`

## Invariants
- None

## Side Effects
- [PhoneBridgeService.kt:29]: `import android.net.Uri`
- [Tools.kt:38]: `import android.net.ConnectivityManager`
- [Tools.kt:39]: `import android.net.NetworkCapabilities`
- [Tools.kt:40]: `import android.net.Uri`

## Verification
- Run: `bazel test //apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/bridge/...`
