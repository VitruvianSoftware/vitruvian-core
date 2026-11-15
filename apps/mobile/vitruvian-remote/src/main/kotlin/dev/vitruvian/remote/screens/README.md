# Screens

## Overview
Component package providing implementation for `apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/screens`.

## Interface
- `[AppsScreen.kt:ColumnScope]`
- `[ConsoleScreen.kt:ColumnScope]`
- `[HomeScreen.kt:ColumnScope]`
- `[HostsScreen.kt:ColumnScope]`
- `[MacScreen.kt:ColumnScope]`
- `[RemoteScreen.kt:ColumnScope]`
- `[RemoteScreen.kt:Trackpad]`
- `[RemoteScreen.kt:Modifier]`

## Invariants
- None

## Side Effects
- [MacScreen.kt:192]: `values = state.net.toList(),`
- [MacScreen.kt:194]: `max = maxOf(state.net.maxOrNull() ?: 0, NET_SPARK_FLOOR),`
- [MacScreen.kt:331]: `VButton("Query", state::runPromql)`

## Verification
- Run: `bazel test //apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/screens/...`
