# State

## Overview
Component package providing implementation for `apps/mobile/android-remote/src/main/kotlin/dev/vitruvian/remote/state`.

## Interface
- `[AgentClient.kt:ExecKind]`
- `[AgentClient.kt:AgentAuthException]`
- `[AgentClient.kt:AgentUnavailableException]`
- `[AgentClient.kt:AgentNotFoundException]`
- `[AgentClient.kt:AgentRequestException]`
- `[AgentClient.kt:ExecStreamHandle]`
- `[AgentClient.kt:AgentClient]`
- `[AgentClient.kt:JSONObject]`
- `[BridgePolicy.kt:ToolTier]`
- `[BridgePolicy.kt:BridgePolicy]`
- `[Clock.kt:Clock]`
- `[Derive.kt:Derive]`
- `[Format.kt:Format]`
- `[Markdown.kt:Markdown]`
- `[MockHost.kt:MockHost]`
- `[Models.kt:Screen]`
- `[Models.kt:Connection]`
- `[Models.kt:MetricsSource]`
- `[Models.kt:AppsView]`
- `[Models.kt:MacroKind]`

## Invariants
- [WakeOnLan.kt:63]: `require(mac.size == MAC_BYTES) { "a MAC address is $MAC_BYTES bytes, got ${ma...`

## Side Effects
- [AgentClient.kt:22]: `import java.net.HttpURLConnection`
- [AgentClient.kt:23]: `import java.net.URL`
- [AgentClient.kt:24]: `import java.net.URLEncoder`
- [MockHost.kt:106]: `// with no build, eval or queue query; the old subtitle promised`
- [RemoteState.kt:41]: `import java.net.DatagramPacket`
- [RemoteState.kt:42]: `import java.net.DatagramSocket`
- [RemoteState.kt:43]: `import java.net.InetAddress`
- [Wire.kt:41]: `* One event from `POST /v1/exec/stream`.`
- [Wire.kt:228]: `* `http://atlas.example.ts.net:7411/` becomes `atlas`, which is what the top-...`
- [Wire.kt:230]: `* intact (without port) so `http://10.0.2.2:7411` is not shortened to `10`.`

## Verification
- Run: `bazel test //apps/mobile/android-remote/src/main/kotlin/dev/vitruvian/remote/state/...`
