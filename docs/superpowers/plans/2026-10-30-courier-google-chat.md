<!--
Copyright 2026 VitruvianSoftware
SPDX-License-Identifier: AGPL-3.0-only
-->

# Courier Google Chat (Network #6) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Google Chat (`gchat`) as Courier's sixth built-in messaging bridge (after WhatsApp, Telegram, Signal, Discord, and Slack), supporting browser-cookie sign-in via macOS `WKWebView`, real-time WebChannel long-polling, DMs and named spaces with inline/threaded replies, rich-text annotations, reactions, edits, unsends, read receipts, typing indicators, and 200 MB Scotty media uploads/downloads.

**Architecture:** Mirror the `apps/desktop/courier/libsignal` hybrid pattern: a pure-Rust static library crate (`apps/desktop/courier/gchat`, compiled via Bazel `rules_rust` into `libgchat_ffi.a` and wrapped in a `cc_library` target `//apps/desktop/courier/gchat:gchat_ffi`) handles Google Chat's `application/x-protobuf` RPCs, descriptor-driven 1-indexed `pblite` JSON array decoding, UTF-16 length-prefixed WebChannel streaming, UTF-16 rich-text annotation conversion, and Scotty media transfers; a thin Go `maunium.net/go/mautrix/bridgev2` connector (`apps/desktop/courier/engine/internal/gchat`) links `gchat_ffi` via `cgo` on `darwin`, registers `"gchat"` in `apps/desktop/courier/engine/internal/networks`, and drives cookie-based sign-in through the existing `WKWebView` `SignInWindowController` and `CookieCollector` in the Swift macOS app.

**Tech Stack:** Rust 2021 (`prost`, `prost-types`, `prost-reflect`, `tokio`, `reqwest` with `rustls-tls`, `serde_json`, `url`), C ABI FFI (`gchat.h`), Go 1.24 (`cgo`, `maunium.net/go/mautrix/bridgev2`, `modernc.org/sqlite`), Swift 6 (`SwiftUI`, `WebKit` `WKWebView` / `WKHTTPCookieStore`), Bazel (`rules_rust`, `rules_go`, `rules_swift`).

**Spec:** [`docs/superpowers/specs/2026-10-30-courier-google-chat-design.md`](../specs/2026-10-30-courier-google-chat-design.md)

---

## Global Constraints

- **License & Attribution (`AGPL-3.0-only`):** Every new source file under `apps/desktop/courier/gchat/` and `apps/desktop/courier/engine/internal/gchat/` MUST carry `SPDX-License-Identifier: AGPL-3.0-only`. Include `apps/desktop/courier/gchat/NOTICE` attributing protocol definitions (`proto/googlechat.proto`), endpoint tables, `pblite` wire semantics, and annotation bitmasks to [`Deniel9204/mautrix-googlechat`](https://github.com/Deniel9204/mautrix-googlechat) at commit `5eeada18f6edc8cb125a46870f6e1ce9ff53f22d` under AGPL-3.0-only.
- **Bazel `rules_rust` + `cgo` Wiring (Mirroring `libsignal`):**
  - `apps/desktop/courier/gchat/BUILD` MUST start with `# gazelle:ignore` so Gazelle's C/C++ extension does not delete `:gchat_ffi` (`cc_library` with `deps = [":gchat_ffi_rust"]` and no `srcs`).
  - `gchat_ffi_rust` is a `rust_static_library` (`crate_name = "gchat_ffi"`) restricted to `target_compatible_with = ["@platforms//os:macos"]`.
  - `gchat_ffi` is a `cc_library` wrapping `:gchat_ffi_rust` with `hdrs = ["include/gchat.h"]`, `includes = ["include"]`, and `linkopts = ["-lc++", "-lz", "-framework", "Security", "-framework", "CoreFoundation"]`, linked by `//apps/desktop/courier/engine/internal/gchat:gchat` via `cgo = True` and `cdeps = ["//apps/desktop/courier/gchat:gchat_ffi"]`.
  - In `MODULE.bazel`, register `crate.from_cargo(name = "gchat_crates", cargo_lock = "//apps/desktop/courier/gchat:Cargo.lock", cargo_toml = "//apps/desktop/courier/gchat:Cargo.toml", platform_triples = ["aarch64-apple-darwin", "x86_64-apple-darwin"])` and wire `prost-build` to `@@//apps/desktop/courier/libsignal:protoc` (`PROTOC` env + `build_script_data`).
- **Platform Scope (`macos_only: true`):** Like `signal`, `gchat` is registered in `platformNetworks()` inside `apps/desktop/courier/engine/internal/networks/networks_signal_darwin.go` (`//go:build darwin`) and omitted on non-darwin builds (`networks_signal_other.go`).
- **Protocol & SQLite Schema Version Placeholders (`next free at build time`):** Milestone 4.6 (`2026-10-25-courier-m4-6-settings-bridges.md`) is concurrently in flight on `main`. Do NOT hardcode integer literals that collide with Milestone 4.6:
  - Whenever this plan references `<NEXT_PROTOCOL_VERSION>` in `apps/desktop/courier/protocol/protocol.json` (if any schema surface is touched; note that adding `"gchat"` to `apps/desktop/courier/protocol/networks.json` does not alter RPC method signatures) or `<NEXT_MIGRATION_NUMBER>` in `apps/desktop/courier/engine/internal/store/migrate.go` (for the `gchat_sessions` / cursor metadata table if persisted outside `bridgev2` KV), resolve to the **next free integer at build time** after Milestone 4.6 lands on `main`.
- **100% Offline Synthetic Fixtures in CI:** Automated tests (`rust_test`, `go_test`, `swift_test`) MUST never contact `*.google.com` or `*.googleusercontent.com` and MUST never require a real Google account. Every protocol test uses synthetic Protobuf frames, synthetic `pblite` JSON arrays, or an ephemeral `127.0.0.1` loopback test server (`offline_test.go` enforces zero external sockets).
- **Cookie Domain Isolation & SSRF Hardening:**
  - Never concatenate cookies into a single flat header string across domains. Maintain a domain-scoped cookie jar: `COMPASS` and `OSID` scoped to `chat.google.com`; `SID`, `HSID`, `SSID`, `APISID`, `SAPISID` (+ `__Secure-1PSID` / `__Secure-3PSID`) scoped to `.google.com`. Never send cookies to `*.googleusercontent.com`.
  - Every `reqwest::Client` in `gchat` MUST set `.no_proxy()`, validate destination hosts against explicit allowlists before sending headers, and resolve DNS through a custom `ReqwestDnsResolver` that rejects loopback, RFC 1918, carrier-grade NAT (`100.64.0.0/10`), link-local (`169.254.0.0/16`, `fe80::/10`), unique-local (`fc00::/7`), multicast, unspecified, and IPv4-embedded IPv6 forms (IPv4-mapped `::ffff:0:0/96`, IPv4-compatible `::/96`, 6to4 `2002::/16`, NAT64 `64:ff9b::/96` & `64:ff9b:1::/48`, Teredo `2001::/32`, ISATAP) — except when a test explicitly passes an `AllowLoopbackForTest` token on `127.0.0.1`.
- **Log Redaction (`logscrub`):** Never log cookie values, `xsrf_token`, message bodies, attachment URLs, raw `pblite` frames, raw `UnexpectedStatusError` URL query strings (`SID`, `AID`, `CI`, `TYPE`), email addresses, or 21-digit Gaia user IDs.

---

## Review Focus

1. **UTF-16 Code-Unit Indexing:** Verify that both `ChunkParser` (`src/channel.rs`) and rich-text `Annotation` slicing (`src/fmt/inbound.rs`, `src/fmt/outbound.rs`) measure offsets and lengths in **UTF-16 code units** (`str::encode_utf16`), never UTF-8 byte indices or Unicode scalar counts (`chars().count()`), so supplementary-plane emojis (surrogate pairs, 2 UTF-16 units / 4 UTF-8 bytes) never panic or skew spans.
2. **64-bit Integer Precision in `pblite`:** Verify `src/pblite.rs` reads `INT64`, `UINT64`, `SINT64`, `FIXED64`, and `SFIXED64` fields from JSON strings (`"1711234567890123"`) as well as JSON numbers without routing through `f64` (preserving microsecond timestamps and 21-digit Gaia IDs above $2^{53} - 1$).
3. **Revision Cursor Separation:** Verify `catch_up_user` and `paginated_world` advances `user_revision` while `catch_up_group` and `Event.group_revision` advances per-room `group_revision`, never mixing the two.
4. **Reaction Variation Selector Normalization:** Verify outbound `update_reaction` strips `U+FE0F` (`\u{fe0f}`) before sending to Google Chat and inbound `Reaction` events restore standard emoji presentation for Courier's UI.
5. **Capability & Registry Parity:** Verify every capability table assertion in `apps/desktop/courier/engine/internal/networks/networks_test.go`, `apps/desktop/courier/engine/internal/actions/features.go` (including the 200 MB file ceiling for `"gchat"`), and `apps/desktop/courier/app/Tests/CourierCoreTests/ChatFeaturesTests.swift` stays green.

---

## Capability Table

### 1. Static & Dynamic Message Capabilities (`GetCapabilities` + `ChatFeatures.forRoom`)

| Feature | Static Value (`GetCapabilities`) | Dynamic Override (`ChatFeatures.forRoom`) | Protocol Backing |
|---|---|---|---|
| `Reply` | `true` | Always `true` | `SendReplyTarget` (`message_id` + microsecond `create_time`) |
| `Thread` | `true` | `true` when `topic_threaded == true`; forced `false` for flat DMs and unthreaded rooms | Topic ID (`GroupId` + `TopicId`) on `create_message` |
| `Edit` | `true` | Always `true` (author's own messages) | `POST /u/0/api/edit_message` |
| `Unsend` | `true` | Always `true` (author's own messages) | `POST /u/0/api/delete_message` |
| `Reaction` (`ReactionCount`) | `-1` (unlimited emoji reactions) | Always enabled | `POST /u/0/api/update_reaction` (`U+FE0F` stripped) |
| `ReadReceipts` | `true` | Always `true` | `POST /u/0/api/mark_group_readstate` |
| `TypingNotifications` | `true` | Always `true` (`6s` receiver TTL) | `POST /u/0/api/set_typing_state` |
| `Formatting` | `[bold, italic, strikethrough, code, pre, bulletList, link, mention]` | Always enabled | `Annotation` types `FORMAT_DATA (9)`, `LINK_DATA (6)`, `USER_MENTION (1)` |
| `MentionRoom` (`@all`) | `true` | `true` in spaces; `false` in 1:1 DMs | `UserMentionMetadata.Type = MENTION_ALL (2)` |
| `MaxTextLength` | `4096` | `4096` | Enforced before `/api/create_message` & `/api/create_topic` |
| `MsgImage`, `MsgVideo`, `MsgAudio`, `CapMsgVoice`, `MsgFile`, `CapMsgGIF` | `SupportSupported` (`MaxSize: 200 * 1024 * 1024`) | `canUploadFile: true`, `maxFileSize: 209_715_200` (200 MiB) | Scotty `/uploads?group_id=<raw_id>`; `actions.networkFileCeiling("gchat") = 200 * 1024 * 1024` |
| `LocationMessages`, `ContactCards`, `Polls`, `Stickers`, `DisappearingTimer`, `Effect` | `SupportUnsupported` (`false`) | Disabled in composer | Not supported on Google Chat |

### 2. Syncs, Receipts, Typing, and Group Management (`networks_test.go` Tables)

| Table in `networks_test.go` | `gchat` Column Expectation | Protocol Backing |
|---|---|---|
| `TestNetworkSyncTableMatchesTheBridges` (`platformClients`) | `sent: ["mute"]`, `implements: ["mute"]` (`MuteHandlingNetworkAPI`) | `POST /u/0/api/update_group_notification_settings` (`MUTED (3)` / `NOTIFY_ALWAYS (1)`) |
| `TestReceiptsTypingAndAccountsTableMatchTheBridges` (`platformReceiptColumns`) | `sends: ["read_receipts", "typing"]`, `replyPrivately: ["resolve_identifier", "create_chat_with_ghost"]`, `implicitReads: false` | `IdentifierResolvingNetworkAPI` + `GhostDMCreatingNetworkAPI` via `POST /u/0/api/create_dm` |
| `TestGroupAndChatManagementTableMatchesTheBridges` (`GroupCapabilitiesOf`) | `SetName: true`, `SetTopic: true`, `SetAvatar: false`, `Membership: true`, `PowerLevels: false`, `DeleteChat: true` | `update_group` (name & `SPACE_DETAILS.description` preserving `guidelines`), `create_membership` (`MEMBER_INVITED`), `remove_memberships`, `hide_group` (`DeleteChat` on DMs; `groupDeleteNeedsEveryone["gchat"] = true` hides `CanDelete` on spaces) |

---

## File Structure

### Created Files (`Create:`)
- `apps/desktop/courier/gchat/BUILD` — Bazel build definition (`# gazelle:ignore`, `rust_static_library`, `cc_library`, `rust_test`).
- `apps/desktop/courier/gchat/Cargo.toml` — Crate manifest for `gchat_ffi`.
- `apps/desktop/courier/gchat/Cargo.lock` — Locked crate dependency graph for `gchat_crates`.
- `apps/desktop/courier/gchat/NOTICE` — AGPL-3.0-only attribution to `Deniel9204/mautrix-googlechat` (`5eeada18f6edc8cb125a46870f6e1ce9ff53f22d`).
- `apps/desktop/courier/gchat/build.rs` — Compiles `proto/googlechat.proto` into `prost` structs + `FileDescriptorSet` bytes (`googlechat_descriptor.bin`) for `prost-reflect`.
- `apps/desktop/courier/gchat/proto/googlechat.proto` — Google Chat `proto2` schema (ported from `mautrix-googlechat` `5eeada18f6edc8cb125a46870f6e1ce9ff53f22d` with `Attachment` field 15 `AppCardData`).
- `apps/desktop/courier/gchat/include/gchat.h` — C ABI header consumed by Go `cgo`.
- `apps/desktop/courier/gchat/src/lib.rs` — Crate root, Tokio runtime manager, handle registry, error mapping.
- `apps/desktop/courier/gchat/src/ffi.rs` — `extern "C"` entrypoints (`gchat_client_new`, `gchat_client_free`, `gchat_bytes_free`, `gchat_validate_session`, `gchat_start_stream`, `gchat_stop_stream`, `gchat_rpc_call`, `gchat_html_to_annotations`, `gchat_annotations_to_html`, `gchat_upload_media`, `gchat_download_media`).
- `apps/desktop/courier/gchat/src/cookies.rs` — Domain-scoped cookie jar, `COMPASS`/`OSID`/`SID`/`HSID`/`SSID` validator, User-Agent normalizer.
- `apps/desktop/courier/gchat/src/netguard.rs` — SSRF IPv4/IPv6 unwrapping DNS resolver, host allowlist validator, `.no_proxy()` client builder.
- `apps/desktop/courier/gchat/src/auth.rs` — `GET /u/0/mole/world` HTML parser for `"xsrf_token":"..."` + 24-hour refresh & single-flight 401/403 re-extraction.
- `apps/desktop/courier/gchat/src/rpc.rs` — `/u/0/api/*` Protobuf RPC caller (`RequestHeader` field 100, `?alt=proto`, base64 body fallback, `429`/`5xx` exponential backoff).
- `apps/desktop/courier/gchat/src/pblite.rs` — Descriptor-driven 1-indexed JSON array (`pblite`) decoder into `prost_reflect::DynamicMessage` (`MaxDepth = 64`, 64-bit string integers, sparse trailing object map).
- `apps/desktop/courier/gchat/src/channel.rs` — WebChannel 4-step handshake (`/register` -> `SID` bind -> Ack `GET` -> `PingEvent` `POST`), UTF-16 `ChunkParser`, `Event.body` / `Event.bodies` splitter, watchdogs, and reconnect backoff ladders.
- `apps/desktop/courier/gchat/src/fmt/mod.rs` — Shared UTF-16 offset helpers and RGB color bitmask utilities.
- `apps/desktop/courier/gchat/src/fmt/inbound.rs` — Google Chat `Annotation` + bot-card (`Attachment` field 15) to Matrix HTML/plain-text converter.
- `apps/desktop/courier/gchat/src/fmt/outbound.rs` — Matrix HTML / Markdown to Google Chat `Annotation` converter.
- `apps/desktop/courier/gchat/src/media.rs` — Scotty 2-step resumable uploader (`/uploads?group_id=`), `/api/get_attachment_url` redirect follower, avatar & gated external image downloader.
- `apps/desktop/courier/gchat/src/fuzz_tests.rs` — Property & fuzz test harnesses (`fuzz_chunk_parser`, `fuzz_pblite_event`, `fuzz_fmt_annotations`).
- `apps/desktop/courier/engine/internal/gchat/BUILD` — Bazel Go library and test targets (`cgo = True`, `target_compatible_with = ["@platforms//os:macos"]`).
- `apps/desktop/courier/engine/internal/gchat/ffi.go` — Go `cgo` bindings over `gchat.h`.
- `apps/desktop/courier/engine/internal/gchat/connector.go` — `GChatConnector` implementing `bridgev2.NetworkConnector`, cookie login flow (`StepCookies`), and `GetName`.
- `apps/desktop/courier/engine/internal/gchat/client.go` — `GChatClient` implementing `bridgev2.NetworkAPI` and optional Courier network interfaces.
- `apps/desktop/courier/engine/internal/gchat/sync.go` — `paginated_world`, `list_topics`, `list_messages`, `catch_up_user` / `catch_up_group`, and live WebChannel event dispatch.
- `apps/desktop/courier/engine/internal/gchat/send.go` — `HandleMatrixMessage`, `HandleMatrixEdit`, `HandleMatrixMessageRemove`, `HandleMatrixReaction`, `HandleMatrixReadReceipt`, `HandleMatrixTyping`, and `local_id` echo deduplication.
- `apps/desktop/courier/engine/internal/gchat/media.go` — Multi-attachment upload/download plumbing (`att_%04d` part IDs, MIME sniffing, 200 MB limit).
- `apps/desktop/courier/engine/internal/gchat/rooms.go` — `ResolveIdentifier`, `CreateChatWithGhost` (`create_dm`), `HandleMute`, `SetChatName`, `SetChatTopic` (`SPACE_DETAILS` preserving `guidelines`), `AddChatMember`, `RemoveChatMember`, `DeleteChat` / `LeaveChat` (`hide_group`).
- `apps/desktop/courier/engine/internal/gchat/gchat_test.go` — Unit tests for connector login, sync, send, media, and room management against synthetic FFI fixtures.
- `apps/desktop/courier/engine/internal/networks/gchat_link_test.go` — Darwin cgo link & FFI round-trip smoke test mirroring `signal_link_test.go`.
- `apps/desktop/courier/engine/docs/gchat-by-hand.md` — Owner's by-hand verification day runbook and acceptance checklist.

### Modified Files (`Modify:` — all verified present with `test -e`)
- `MODULE.bazel` — Add `gchat_crates` via `crate.from_cargo` and `crate.annotation` for `prost-build` (`protoc`).
- `apps/desktop/courier/protocol/networks.json` — Append `{ "name": "gchat", "display_name": "Google Chat", "macos_only": true }`.
- `apps/desktop/courier/engine/internal/networks/BUILD` — Add `//apps/desktop/courier/engine/internal/gchat` to darwin `select()` deps and add `gchat_link_test`.
- `apps/desktop/courier/engine/internal/networks/networks_signal_darwin.go` — Register `"gchat"` in `platformNetworks()` alongside `"signal"`.
- `apps/desktop/courier/engine/internal/networks/signal_registered_darwin_test.go` — Assert both `"signal"` and `"gchat"` are registered on `darwin`.
- `apps/desktop/courier/engine/internal/networks/signal_absent_other_test.go` — Assert neither `"signal"` nor `"gchat"` is registered on non-darwin.
- `apps/desktop/courier/engine/internal/networks/networks_test.go` — Add `"gchat"` to `platformClients()`, `platformActionRows()`, `platformReceiptColumns()`, and `TestGroupAndChatManagementTableMatchesTheBridges`.
- `apps/desktop/courier/engine/internal/actions/features.go` — Set `groupDeleteNeedsEveryone["gchat"] = true`, update `networkFileCeiling("gchat")` to `200 * 1024 * 1024`, and document `topic_threaded` dynamic `CanThread` handling.
- `apps/desktop/courier/engine/internal/logscrub/logscrub.go` — Add scrubbing rules for 21-digit Gaia IDs (`1\d{20}` in user contexts), `COMPASS=`/`OSID=`/`SID=` cookies, `xsrf_token`, and WebChannel URL query parameters (`SID=`, `AID=`, `CI=`).
- `apps/desktop/courier/engine/internal/logscrub/bridge_test.go` — Add redaction test cases for Google Chat tokens, Gaia IDs, emails, and `UnexpectedStatusError` query strings.
- `apps/desktop/courier/app/Sources/CourierCore/ChatFeatures.swift` — Add `"gchat": "Google Chat"` to `NetworkNames.names`.
- `apps/desktop/courier/app/Sources/CourierCore/InboxPresentation.swift` — Add `"gchat"` icon/badge case to `NetworkAppearance.of(_:)`.
- `apps/desktop/courier/app/Sources/CourierCore/LoginFlowModel.swift` — Add `"gchat": ["cookies"]` to `preferredFlows` and `case ("gchat", "cookies"): String(localized: "Google account")` to `flowName(_:network:)`.
- `apps/desktop/courier/app/Tests/CourierCoreTests/ChatFeaturesTests.swift` — Add test verifying `ChatFeatures.forRoom` toggles `canThread` from `topic_threaded` and exposes the 200 MB file ceiling for `"gchat"`.
- `apps/desktop/courier/app/Tests/CourierCoreTests/CookieCollectorTests.swift` — Add domain-scoped Google Chat cookie collection test (`chat.google.com` vs `.google.com`).
- `apps/desktop/courier/app/Tests/CourierCoreTests/LoginFlowModelTests.swift` — Add test verifying Google Chat's `"cookies"` login flow label and `StepCookies` handling.

---

## Milestone 1: Crate Skeleton & Auth

### Task 1: Bazel `rules_rust` Static Library (`apps/desktop/courier/gchat`) & `MODULE.bazel` Wiring

**Files:**
- Create: `apps/desktop/courier/gchat/NOTICE`
- Create: `apps/desktop/courier/gchat/Cargo.toml`
- Create: `apps/desktop/courier/gchat/Cargo.lock`
- Create: `apps/desktop/courier/gchat/BUILD`
- Create: `apps/desktop/courier/gchat/build.rs`
- Create: `apps/desktop/courier/gchat/proto/googlechat.proto`
- Create: `apps/desktop/courier/gchat/include/gchat.h`
- Create: `apps/desktop/courier/gchat/src/lib.rs`
- Create: `apps/desktop/courier/gchat/src/ffi.rs`
- Modify: `MODULE.bazel`

**Interfaces:**
```c
// apps/desktop/courier/gchat/include/gchat.h
// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only
#ifndef COURIER_GCHAT_H
#define COURIER_GCHAT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct GChatClient GChatClient;

typedef enum GChatStatus {
  GCHAT_OK = 0,
  GCHAT_ERR_INVALID_ARG = 1,
  GCHAT_ERR_AUTH_EXPIRED = 2,
  GCHAT_ERR_RATE_LIMITED = 3,
  GCHAT_ERR_TRANSIENT = 4,
  GCHAT_ERR_SSRF_BLOCKED = 5,
  GCHAT_ERR_PROTOCOL = 6,
  GCHAT_ERR_INTERNAL = 7,
} GChatStatus;

typedef struct GChatByteSlice {
  uint8_t *ptr;
  size_t len;
} GChatByteSlice;

typedef void (*GChatEventCallback)(
    uintptr_t userdata,
    int32_t event_kind,
    const uint8_t *payload_ptr,
    size_t payload_len);

GChatStatus gchat_client_new(
    const uint8_t *config_json_ptr,
    size_t config_json_len,
    GChatClient **out_client,
    GChatByteSlice *out_err);

void gchat_client_free(GChatClient *client);
void gchat_bytes_free(GChatByteSlice slice);

GChatStatus gchat_validate_session(
    GChatClient *client,
    GChatByteSlice *out_self_json,
    GChatByteSlice *out_err);

GChatStatus gchat_start_stream(
    GChatClient *client,
    GChatEventCallback cb,
    uintptr_t userdata,
    GChatByteSlice *out_err);

void gchat_stop_stream(GChatClient *client);

GChatStatus gchat_rpc_call(
    GChatClient *client,
    const char *endpoint_ptr,
    size_t endpoint_len,
    const uint8_t *req_proto_ptr,
    size_t req_proto_len,
    GChatByteSlice *out_resp_proto,
    GChatByteSlice *out_err);

GChatStatus gchat_html_to_annotations(
    const uint8_t *input_json_ptr,
    size_t input_json_len,
    GChatByteSlice *out_result_json,
    GChatByteSlice *out_err);

GChatStatus gchat_annotations_to_html(
    const uint8_t *input_proto_ptr,
    size_t input_proto_len,
    GChatByteSlice *out_result_json,
    GChatByteSlice *out_err);

GChatStatus gchat_upload_media(
    GChatClient *client,
    const uint8_t *req_json_ptr,
    size_t req_json_len,
    const uint8_t *data_ptr,
    size_t data_len,
    GChatByteSlice *out_upload_proto,
    GChatByteSlice *out_err);

GChatStatus gchat_download_media(
    GChatClient *client,
    const uint8_t *req_json_ptr,
    size_t req_json_len,
    GChatByteSlice *out_bytes,
    GChatByteSlice *out_err);

#ifdef __cplusplus
}
#endif

#endif  // COURIER_GCHAT_H
```

- [ ] **Step 1: Create `apps/desktop/courier/gchat/NOTICE` and `proto/googlechat.proto`**
  Write `apps/desktop/courier/gchat/NOTICE` with the AGPL-3.0-only notice attributing [`Deniel9204/mautrix-googlechat`](https://github.com/Deniel9204/mautrix-googlechat) at commit `5eeada18f6edc8cb125a46870f6e1ce9ff53f22d`. Port `googlechat.proto` into `apps/desktop/courier/gchat/proto/googlechat.proto` (`syntax = "proto2"; package googlechat;`) including `RequestHeader`, `ClientFeatureCapabilities`, `Event`, `Event.EventBody`, `WebChannelEvent`, `PingEvent`, `Message`, `MessageId`, `MessageParentId`, `TopicId`, `GroupId`, `SpaceId`, `DmId`, `UserId`, `User`, `Group`, `Annotation` (types `USER_MENTION = 1`, `SLASH_COMMAND = 2`, `DRIVE_METADATA = 3`, `YOUTUBE_METADATA = 4`, `GSUITE_INTEGRATION_METADATA = 5`, `LINK_DATA = 6`, `GROUP_RETENTION_SETTINGS_UPDATED = 7`, `BABEL_PLACEHOLDER = 8`, `FORMAT_DATA = 9`, `READ_RECEIPTS_SETTINGS_METADATA = 10`, `CONSENT_SETTINGS_METADATA = 11`, `VIDEO_CALL_METADATA = 13`, ` UPLOAD_METADATA = 14`, `CARD_CAPABILITY_METADATA = 15`), `Attachment` (with `UploadMetadata` at field 14 and `AppCardData` / bot-card fallback at field 15), `Reaction`, `PaginatedWorldRequest`/`Response`, `CreateTopicRequest`/`Response`, `CreateMessageRequest`/`Response`, `EditMessageRequest`/`Response`, `DeleteMessageRequest`/`Response`, `UpdateReactionRequest`/`Response`, `MarkGroupReadstateRequest`/`Response`, `SetTypingStateRequest`/`Response`, `ListTopicsRequest`/`Response`, `ListMessagesRequest`/`Response`, `CatchUpUserRequest`/`Response`, `CatchUpGroupRequest`/`Response`, `GetGroupRequest`/`Response`, `GetMembersRequest`/`Response`, `CreateDmRequest`/`Response`, `HideGroupRequest`/`Response`, `UpdateGroupRequest`/`Response`, `UpdateGroupNotificationSettingsRequest`/`Response`, `CreateMembershipRequest`/`Response`, `RemoveMembershipsRequest`/`Response`, `GetSelfUserStatusRequest`/`Response`, and `GetAttachmentUrlRequest`/`Response`.

- [ ] **Step 2: Create `Cargo.toml`, `build.rs`, `include/gchat.h`, `src/lib.rs`, and `src/ffi.rs`**
  In `apps/desktop/courier/gchat/Cargo.toml`, declare `[package] name = "gchat_ffi"`, `edition = "2021"`, `license = "AGPL-3.0-only"`, `[lib] crate-type = ["staticlib", "rlib"]`, dependencies (`prost`, `prost-types`, `prost-reflect`, `serde`, `serde_json`, `tokio`, `reqwest` with `rustls-tls`, `url`, `base64`, `bytes`, `thiserror`, `html5ever` / `scraper` or `tl`), and `[build-dependencies] prost-build`, `prost-reflect-build`.
  In `build.rs`, compile `proto/googlechat.proto` using `prost_reflect_build::Builder::new().file_descriptor_set_bytes("DESCRIPTOR_BYTES")` into `OUT_DIR/googlechat.rs` and `OUT_DIR/googlechat_descriptor.bin`.
  In `src/lib.rs` and `src/ffi.rs`, wire `DESCRIPTOR_POOL` (`LazyLock<prost_reflect::DescriptorPool>`), `GChatClient` handle lifecycle, and a unit test `tests::descriptor_pool_loads_googlechat_proto` asserting `DescriptorPool::decode(DESCRIPTOR_BYTES)` resolves `googlechat.Event`, `googlechat.Message`, `googlechat.Annotation`, and `googlechat.Attachment` field 15.

- [ ] **Step 3: Create `apps/desktop/courier/gchat/BUILD` and wire `gchat_crates` in `MODULE.bazel`**
  Write `apps/desktop/courier/gchat/BUILD` mirroring `apps/desktop/courier/libsignal/BUILD`:
  ```python
  # Copyright 2026 VitruvianSoftware
  # SPDX-License-Identifier: AGPL-3.0-only

  # gazelle:ignore
  # Gazelle's C/C++ extension does not know about rust_static_library and will
  # delete :gchat_ffi (a cc_library with no srcs of its own). This package is
  # maintained by hand.

  load("@gchat_crates//:defs.bzl", "all_crate_deps")
  load("@rules_cc//cc:defs.bzl", "cc_library")
  load("@rules_rust//cargo:defs.bzl", "cargo_build_script")
  load("@rules_rust//rust:defs.bzl", "rust_static_library", "rust_test")

  cargo_build_script(
      name = "gchat_build_script",
      srcs = ["build.rs"],
      build_script_env = {
          "PROTOC": "$(execpath //apps/desktop/courier/libsignal:protoc)",
      },
      Compile_data = ["proto/googlechat.proto"],
      data = ["proto/googlechat.proto"],
      tools = ["//apps/desktop/courier/libsignal:protoc"],
      deps = all_crate_deps(build = True),
  )

  rust_static_library(
      name = "gchat_ffi_rust",
      srcs = glob(["src/**/*.rs"]),
      compile_data = ["proto/googlechat.proto"],
      crate_name = "gchat_ffi",
      edition = "2021",
      proc_macro_deps = all_crate_deps(proc_macro = True),
      target_compatible_with = ["@platforms//os:macos"],
      deps = all_crate_deps(normal = True) + [":gchat_build_script"],
  )

  cc_library(
      name = "gchat_ffi",
      hdrs = ["include/gchat.h"],
      includes = ["include"],
      linkopts = [
          "-lc++",
          "-lz",
          "-framework",
          "Security",
          "-framework",
          "CoreFoundation",
      ],
      target_compatible_with = ["@platforms//os:macos"],
      visibility = ["//visibility:public"],
      deps = [":gchat_ffi_rust"],
  )

  rust_test(
      name = "gchat_ffi_test",
      crate = ":gchat_ffi_rust",
      target_compatible_with = ["@platforms//os:macos"],
  )
  ```
  Update `MODULE.bazel` to register `gchat_crates` via `crate.from_cargo` and lock `apps/desktop/courier/gchat/Cargo.lock` with `bazel run //tools/crates:lock`.

- [ ] **Step 4: Run the crate build and descriptor unit test**
  Run: `bazel test //apps/desktop/courier/gchat:gchat_ffi_test && bazel build //apps/desktop/courier/gchat:gchat_ffi`
  Expected: `PASS` (`descriptor_pool_loads_googlechat_proto` passes and `libgchat_ffi.a` compiles cleanly).

- [ ] **Step 5: Commit Task 1**
  Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): scaffold gchat_ffi Rust crate and proto descriptors" MODULE.bazel apps/desktop/courier/gchat`

---

### Task 2: Domain-Scoped Cookie Jar, `/u/0/mole/world` XSRF Bootstrap, & Protobuf RPC Caller

**Files:**
- Create: `apps/desktop/courier/gchat/src/cookies.rs`
- Create: `apps/desktop/courier/gchat/src/netguard.rs`
- Create: `apps/desktop/courier/gchat/src/auth.rs`
- Create: `apps/desktop/courier/gchat/src/rpc.rs`
- Modify: `apps/desktop/courier/gchat/src/lib.rs`
- Modify: `apps/desktop/courier/gchat/src/ffi.rs`

**Interfaces:**
```rust
// apps/desktop/courier/gchat/src/cookies.rs
pub const DEFAULT_MACOS_SAFARI_UA: &str =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15";

#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct ScopedCookie {
    pub name: String,
    pub value: String,
    pub domain: String,
    pub path: String,
}

pub struct DomainCookieJar {
    cookies: Vec<ScopedCookie>,
}

impl DomainCookieJar {
    pub fn from_scoped_cookies(cookies: Vec<ScopedCookie>) -> Result<Self, GChatError>;
    pub fn cookie_header_for_url(&self, url: &url::Url) -> Option<String>;
}

pub fn normalize_user_agent(raw: Option<&str>) -> String;
```

```rust
// apps/desktop/courier/gchat/src/auth.rs
pub fn extract_xsrf_token_from_mole_world_html(html: &str) -> Result<String, GChatError>;

pub struct XsrfTokenManager {
    // Caches token with 24h TTL + single-flight refresh mutex on 401/403
}
```

```rust
// apps/desktop/courier/gchat/src/rpc.rs
pub const SUPPORTED_CAPABILITIES: &[(i32, i32)] = &[
    // Field 4 repeated ClientFeatureCapabilities on RequestHeader (field 100)
];

pub fn build_request_header() -> googlechat::RequestHeader;

pub async fn invoke_proto_rpc(
    http: &reqwest::Client,
    jar: &DomainCookieJar,
    xsrf: &XsrfTokenManager,
    base_url: &url::Url,
    endpoint: &str,
    req_bytes: &[u8],
) -> Result<Vec<u8>, GChatError>;
```

- [ ] **Step 1: Write failing unit tests for domain-scoped cookies, User-Agent normalization, XSRF extraction, and RPC retry/base64 decoding**
  In `src/cookies.rs`, `src/auth.rs`, and `src/rpc.rs`, write unit tests:
  - `test_cookie_jar_validates_required_five_cookies_and_scopes_by_host`:
    - Rejects jar missing any of `COMPASS`, `OSID` (on `chat.google.com`) or `SID`, `HSID`, `SSID` (on `.google.com`).
    - For `https://chat.google.com/u/0/api/get_self_user_status?alt=proto`, emits `COMPASS`, `OSID`, `SID`, `HSID`, `SSID`, plus optional `APISID`, `SAPISID`, `__Secure-1PSID`, `__Secure-3PSID`.
    - For `https://lh3.googleusercontent.com/a/avatar`, returns `None` (never sends cookies to `*.googleusercontent.com`).
  - `test_normalize_user_agent_rejects_control_chars_and_defaults_to_safari`:
    - Strips or rejects `\r`, `\n`, `\0` and falls back to `DEFAULT_MACOS_SAFARI_UA` when empty or > 512 bytes.
  - `test_extract_xsrf_token_from_mole_world_html`:
    - Parses synthetic `/u/0/mole/world` HTML containing `..."xsrf_token":"AF1QipP_synthetic_token:1710000000000"...` and extracts `"AF1QipP_synthetic_token:1710000000000"` without evaluating JS.
    - Returns `GChatError::AuthExpired` when the response redirects to `accounts.google.com/ServiceLogin` or lacks `"xsrf_token"`.
  - `test_rpc_caller_attaches_header_retries_429_and_decodes_base64_fallback`:
    - Starts a local `127.0.0.1` test server (`AllowLoopbackForTest`).
    - Verifies `X-Goog-Encode-Response-If-Executable: base64`, `Content-Type: application/x-protobuf`, `Origin: https://chat.google.com`, `Referer: https://chat.google.com/`, and `x-framework-xsrf-token`.
    - Simulates a `429` with `Retry-After: 0`, then returns a base64-encoded `GetSelfUserStatusResponse` (`X-Goog-Safety-Encoding: base64`), and verifies `invoke_proto_rpc` decodes the inner `User` (`UserId.id = "112233445566778899001"`, `name = "Ada Lovelace"`, `email = "ada@example.com"`).
    - Simulates a single `401` and verifies `XsrfTokenManager` refreshes `/u/0/mole/world` once under single-flight lock and retries; on a second `401`, returns `GChatError::AuthExpired`.

- [ ] **Step 2: Run `bazel test //apps/desktop/courier/gchat:gchat_ffi_test` to confirm failure**
  Run: `bazel test //apps/desktop/courier/gchat:gchat_ffi_test`
  Expected: FAIL (functions not implemented yet).

- [ ] **Step 3: Implement `cookies.rs`, `auth.rs`, `rpc.rs`, and wire `gchat_validate_session` in `ffi.rs`**
  Implement `DomainCookieJar`, `normalize_user_agent`, `extract_xsrf_token_from_mole_world_html`, `XsrfTokenManager` (with 24-hour background refresh timer and single-flight `tokio::sync::Mutex`), and `invoke_proto_rpc` (injecting `RequestHeader` at field 100 with `ClientType = IOS (3)`, `locale = "en"`, and `ClientFeatureCapabilities`, capped at 3 attempts with exponential backoff `1s -> 2s -> 4s` + 25% jitter and 15s per-request timeout). Wire `gchat_validate_session` to call `/u/0/mole/world` followed by `POST /u/0/api/get_self_user_status?alt=proto` and return JSON `{"gaia_id": "...", "name": "...", "email": "...", "avatar_url": "..."}`.

- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/gchat:gchat_ffi_test` to confirm green**
  Run: `bazel test //apps/desktop/courier/gchat:gchat_ffi_test`
  Expected: PASS.

- [ ] **Step 5: Commit Task 2**
  Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): add gchat domain-scoped cookie jar, XSRF bootstrap, and proto RPC caller" apps/desktop/courier/gchat`

---

### Task 3: Go `cgo` Connector Skeleton, `"cookies"` Login Flow, Network Registration, & Swift App Sign-In Wiring

**Files:**
- Create: `apps/desktop/courier/engine/internal/gchat/BUILD`
- Create: `apps/desktop/courier/engine/internal/gchat/ffi.go`
- Create: `apps/desktop/courier/engine/internal/gchat/connector.go`
- Create: `apps/desktop/courier/engine/internal/gchat/client.go`
- Create: `apps/desktop/courier/engine/internal/gchat/gchat_test.go`
- Create: `apps/desktop/courier/engine/internal/networks/gchat_link_test.go`
- Modify: `apps/desktop/courier/protocol/networks.json`
- Modify: `apps/desktop/courier/engine/internal/networks/BUILD`
- Modify: `apps/desktop/courier/engine/internal/networks/networks_signal_darwin.go`
- Modify: `apps/desktop/courier/engine/internal/networks/signal_registered_darwin_test.go`
- Modify: `apps/desktop/courier/engine/internal/networks/signal_absent_other_test.go`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ChatFeatures.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/InboxPresentation.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/LoginFlowModel.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/CookieCollectorTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/LoginFlowModelTests.swift`

**Interfaces:**
```go
// apps/desktop/courier/engine/internal/gchat/connector.go
package gchat

const (
	NetworkID   = "gchat"
	DisplayName = "Google Chat"
	FlowCookies = "cookies"
)

func NewConnector() bridgev2.NetworkConnector
```

```go
// Cookie login StepCookies emitted by GChatLogin.Start(ctx):
&bridgev2.LoginStep{
	Type:         bridgev2.LoginStepTypeCookies,
	StepID:       "fi.mau.gchat.login.cookies",
	Instructions: "Sign in to your Google account in the browser window.",
	CookiesParams: &bridgev2.LoginCookiesParams{
		URL:               "https://chat.google.com/",
		UserAgent:         "", // Uses SignInPage.safariApplicationName in WKWebView
		WaitForURLPattern: `^https://chat\.google\.com/`,
		Fields: []bridgev2.LoginCookieField{
			{ID: "COMPASS", Required: true, Sources: []bridgev2.LoginCookieSource{{Type: bridgev2.LoginCookieTypeCookie, Name: "COMPASS", CookieDomain: "chat.google.com"}}},
			{ID: "OSID", Required: true, Sources: []bridgev2.LoginCookieSource{{Type: bridgev2.LoginCookieTypeCookie, Name: "OSID", CookieDomain: "chat.google.com"}}},
			{ID: "SID", Required: true, Sources: []bridgev2.LoginCookieSource{{Type: bridgev2.LoginCookieTypeCookie, Name: "SID", CookieDomain: "google.com"}}},
			{ID: "HSID", Required: true, Sources: []bridgev2.LoginCookieSource{{Type: bridgev2.LoginCookieTypeCookie, Name: "HSID", CookieDomain: "google.com"}}},
			{ID: "SSID", Required: true, Sources: []bridgev2.LoginCookieSource{{Type: bridgev2.LoginCookieTypeCookie, Name: "SSID", CookieDomain: "google.com"}}},
			{ID: "APISID", Required: false, Sources: []bridgev2.LoginCookieSource{{Type: bridgev2.LoginCookieTypeCookie, Name: "APISID", CookieDomain: "google.com"}}},
			{ID: "SAPISID", Required: false, Sources: []bridgev2.LoginCookieSource{{Type: bridgev2.LoginCookieTypeCookie, Name: "SAPISID", CookieDomain: "google.com"}}},
			{ID: "__Secure-1PSID", Required: false, Sources: []bridgev2.LoginCookieSource{{Type: bridgev2.LoginCookieTypeCookie, Name: "__Secure-1PSID", CookieDomain: "google.com"}}},
			{ID: "__Secure-3PSID", Required: false, Sources: []bridgev2.LoginCookieSource{{Type: bridgev2.LoginCookieTypeCookie, Name: "__Secure-3PSID", CookieDomain: "google.com"}}},
			{ID: "user_agent", Required: false, Sources: []bridgev2.LoginCookieSource{{Type: bridgev2.LoginCookieTypeSpecial, Name: "user_agent"}}},
		},
	},
}
```

- [ ] **Step 1: Write failing tests in Go and Swift for `gchat` registration and cookie sign-in**
  - Create `apps/desktop/courier/engine/internal/networks/gchat_link_test.go` (`//go:build darwin`) testing `gchat.LinkCheck()` (round-tripping a synthetic `Annotation` conversion through `libgchat_ffi.a` via `cgo`).
  - Update `apps/desktop/courier/engine/internal/networks/signal_registered_darwin_test.go` to assert both `"signal"` and `"gchat"` are present in `All()` on `darwin`.
  - Update `apps/desktop/courier/engine/internal/networks/signal_absent_other_test.go` to assert neither `"signal"` nor `"gchat"` is present on non-darwin.
  - Create `apps/desktop/courier/engine/internal/gchat/gchat_test.go` with `TestGChatCookieLoginFlowCreatesUserLogin`: starts the `"cookies"` flow, verifies the `LoginCookiesParams` fields and domains (`chat.google.com` vs `google.com`), submits synthetic cookies against a loopback `/u/0/mole/world` + `/u/0/api/get_self_user_status` fixture, and asserts `UserLogin` is created with ID `112233445566778899001` and remote name `"Ada Lovelace (ada@example.com)"`.
  - In `apps/desktop/courier/app/Tests/CourierCoreTests/CookieCollectorTests.swift`, add `testCollectsGoogleChatDomainScopedCookies` verifying `CookieCollector.collect` matches `COMPASS` and `OSID` from `chat.google.com` and `SID`, `HSID`, `SSID` from `.google.com` once `currentURL` reaches `https://chat.google.com/u/0/`.
  - In `apps/desktop/courier/app/Tests/CourierCoreTests/LoginFlowModelTests.swift`, add `testGoogleChatPreferredFlowIsCookiesAndDisplaysGoogleAccount`.

- [ ] **Step 2: Update `protocol/networks.json`, Go `gchat` package, `networks_signal_darwin.go`, and Swift `CourierCore` files**
  - Append `{ "name": "gchat", "display_name": "Google Chat", "macos_only": true }` to `apps/desktop/courier/protocol/networks.json`.
  - Create `apps/desktop/courier/engine/internal/gchat/BUILD`, `ffi.go`, `connector.go`, and `client.go`.
  - Update `apps/desktop/courier/engine/internal/networks/BUILD` and `apps/desktop/courier/engine/internal/networks/networks_signal_darwin.go` to register `"gchat"` (`DisplayName: "Google Chat"`, `Flows: []string{"cookies"}`, `Spec: gchatSpec`).
  - Update `apps/desktop/courier/app/Sources/CourierCore/ChatFeatures.swift` (`"gchat": "Google Chat"` in `NetworkNames.names`), `InboxPresentation.swift` (`case "gchat":` in `NetworkAppearance.of(_:)`), and `LoginFlowModel.swift` (`"gchat": ["cookies"]` in `preferredFlows` and `case ("gchat", "cookies"): String(localized: "Google account")` in `flowName(_:network:)`).

- [ ] **Step 3: Run Go and Swift tests**
  Run: `bazel test //apps/desktop/courier/engine/internal/gchat:gchat_test //apps/desktop/courier/engine/internal/networks:gchat_link_test //apps/desktop/courier/app:CourierCoreTests`
  Expected: PASS.

- [ ] **Step 4: Commit Task 3**
  Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): wire gchat cgo connector, cookie login flow, and Swift app sign-in" apps/desktop/courier/protocol/networks.json apps/desktop/courier/engine/internal/gchat apps/desktop/courier/engine/internal/networks apps/desktop/courier/app`

---

## Milestone 2: Read Path

### Task 4: Descriptor-Driven `pblite` 1-Indexed JSON Array Codec (`src/pblite.rs`)

**Files:**
- Create: `apps/desktop/courier/gchat/src/pblite.rs`
- Modify: `apps/desktop/courier/gchat/src/lib.rs`

**Interfaces:**
```rust
// apps/desktop/courier/gchat/src/pblite.rs
pub const MAX_PBLITE_DEPTH: usize = 64;

/// Decodes a 1-indexed pblite JSON array value into a protobuf message of type `M`
/// using `prost_reflect::MessageDescriptor`.
pub fn decode_pblite<M: prost::Message + Default>(
    desc: &prost_reflect::MessageDescriptor,
    value: &serde_json::Value,
) -> Result<M, GChatError>;

pub fn decode_pblite_dynamic(
    desc: &prost_reflect::MessageDescriptor,
    value: &serde_json::Value,
    depth: usize,
) -> Result<prost_reflect::DynamicMessage, GChatError>;
```

- [ ] **Step 1: Write failing unit tests for `pblite` decoding in `src/pblite.rs`**
  Write tests covering every wire invariant from Spec §2.3:
  - `test_pblite_maps_one_indexed_array_positions_to_field_numbers`: array index `i` maps to Protobuf tag `i + 1`.
  - `test_pblite_merges_trailing_sparse_object_keys_in_numeric_order`: when the last element of a `pblite` array is a JSON object `{"100": [...], "15": [...]}` (and field `N` is not itself a `map<K,V>`), keys are parsed as integer tags, sorted ascending (`15`, then `100`), and merged into the message.
  - `test_pblite_preserves_64bit_integer_precision_from_strings`: a 64-bit microsecond timestamp `"1711234567890123"` and 21-digit Gaia ID `"112233445566778899001"` on `INT64`/`UINT64`/`STRING` fields decode without `f64` truncation.
  - `test_pblite_decodes_bool_from_0_1_and_bytes_from_base64`: integer `0`/`1` and `false`/`true` both decode as `bool`; base64 strings decode into `bytes`.
  - `test_pblite_skips_null_and_unknown_tags_without_error`: `null` elements and unknown high tags are ignored cleanly.
  - `test_pblite_enforces_max_depth_64`: a 65-level nested JSON array returns `GChatError::Protocol("max pblite nesting depth 64 exceeded")` without stack overflow.
  - `test_pblite_decodes_webchannel_event_with_nested_event_bodies`: decodes a synthetic `WebChannelEvent` containing an `Event` with both singular `body` (field 4) and repeated `bodies` (field 8).

- [ ] **Step 2: Run `bazel test //apps/desktop/courier/gchat:gchat_ffi_test` to confirm failure**
  Run: `bazel test //apps/desktop/courier/gchat:gchat_ffi_test`
  Expected: FAIL.

- [ ] **Step 3: Implement `src/pblite.rs`**
  Implement `decode_pblite` and `decode_pblite_dynamic` using `prost_reflect::DynamicMessage::new(desc)`, handling 1-indexed array slots, trailing sparse JSON object maps (checking `!field_at_last_index.is_map()`), string-encoded 64-bit integers (`str::parse::<i64>()` / `str::parse::<u64>()`), `0`/`1` booleans, enums by number, nested submessages, repeated lists, and `depth > MAX_PBLITE_DEPTH` rejection, then transcoding to `M` via `DynamicMessage::transcode_to()`.

- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/gchat:gchat_ffi_test` to confirm green**
  Run: `bazel test //apps/desktop/courier/gchat:gchat_ffi_test`
  Expected: PASS.

- [ ] **Step 5: Commit Task 4**
  Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): implement descriptor-driven pblite JSON array decoder" apps/desktop/courier/gchat`

---

### Task 5: WebChannel 4-Step Handshake, UTF-16 `ChunkParser`, Event Splitter, & Reconnect Backoff (`src/channel.rs`)

**Files:**
- Create: `apps/desktop/courier/gchat/src/channel.rs`
- Modify: `apps/desktop/courier/gchat/src/lib.rs`
- Modify: `apps/desktop/courier/gchat/src/ffi.rs`

**Interfaces:**
```rust
// apps/desktop/courier/gchat/src/channel.rs
pub const MAX_CHUNK_UTF16_UNITS: usize = 16 * 1024 * 1024; // 16 MiB cap

pub struct ChunkParser {
    utf8_Carry: Vec<u8>,
    utf16_buf: Vec<u16>,
}

impl ChunkParser {
    pub fn new() -> Self;
    /// Feeds arbitrary network byte slices (including mid-codepoint splits),
    /// extracts complete `<len>\n<payload>` frames measured in UTF-16 code units,
    /// and resyncs in O(n) single-pass on desync without quadratic scanning.
    pub fn push_bytes(&mut self, bytes: &[u8]) -> Result<Vec<String>, GChatError>;
}

/// Extracts all EventBody entries in order: singular `event.body` (field 4) first,
/// followed by all entries in repeated `event.bodies` (field 8).
pub fn extract_event_bodies(event: &googlechat::Event) -> Vec<googlechat::event::EventBody>;
```

- [ ] **Step 1: Write failing unit tests for `ChunkParser`, `extract_event_bodies`, and the 4-step WebChannel lifecycle**
  In `src/channel.rs`, write unit tests:
  - `test_chunk_parser_counts_utf16_code_units_across_split_4byte_emojis`:
    - Construct a payload containing supplementary-plane emojis (`"🔥🎉"` = 4 UTF-16 code units, 8 UTF-8 bytes) inside a JSON frame.
    - Split the raw UTF-8 stream right in the middle of the 4-byte sequence `\xF0\x9F` / `\x94\xA5` across two `push_bytes` calls.
    - Verify `ChunkParser` holds back the incomplete trailing UTF-8 sequence, measures the frame length in UTF-16 code units, and yields the exact JSON string on the second call.
  - `test_chunk_parser_rejects_oversized_frame_and_resyncs_in_single_pass`:
    - Feed a frame prefix claiming `20000000\n` (> 16M UTF-16 units) and assert `GChatError::Protocol`.
    - Feed corrupted garbage followed by `\n12\n[[1,["noop"]]]` and verify single-pass resync recovers the valid frame.
  - `test_extract_event_bodies_emits_field_4_then_field_8_in_order`:
    - Build a `googlechat::Event` with 1 item in `body` (field 4) and 2 items in `bodies` (field 8); assert `extract_event_bodies` returns all 3 in order.
  - `test_webchannel_four_step_handshake_and_aid_progression`:
    - Start a local `127.0.0.1` mock WebChannel server (`AllowLoopbackForTest`).
    - Assert Step 1 (`POST /u/0/webchannel/register` with `X-Goog-Encode-Response-If-Executable: base64`), Step 2 (`POST /u/0/webchannel/events_encoded?...&RID=<rid>&CVER=22&X-HTTP-Session-Id=gsessionid` returning `[[0,["c","sid_123","",8]]]`), Step 3 (`GET /u/0/webchannel/events_encoded?gsessionid=...&SID=sid_123&RID=rpc&AID=0&CI=0&TYPE=xmlhttp` streaming length-prefixed chunks `[[1,[...]]]` and `[[2,[...]]]`), and Step 4 (initial `POST` with `count=1&ofs=0&req0___data__=<json>` carrying `PingEvent { state: ACTIVE, application_focus_state: FOCUS_STATE_FOREGROUND, client_Interactive_state: INTERACTIVE, client_notifications_enabled: true }`).
    - Assert `AID` updates to `2` after chunk `[[2,[...]]]`.

- [ ] **Step 2: Run `bazel test //apps/desktop/courier/gchat:gchat_ffi_test` to confirm failure**
  Run: `bazel test //apps/desktop/courier/gchat:gchat_ffi_test`
  Expected: FAIL.

- [ ] **Step 3: Implement `src/channel.rs` and wire `gchat_start_stream` / `gchat_stop_stream` in `ffi.rs`**
  Implement `ChunkParser`, `extract_event_bodies`, the 4-step WebChannel state machine, the 60s client `PingEvent` ticker, the 35s read-inactivity watchdog, the 90s server-event watchdog, normal long-poll rotation (`AID` preserved), and the two backoff ladders:
  - Normal stream drop / `400 Unknown SID`: fresh `/webchannel/register` with `1s -> 2s -> 4s -> 8s -> 15s -> 30s` (+25% jitter) and trigger a catch-up notification callback to Go.
  - Fatal `401`/`403` after `/u/0/mole/world` refresh fails: emit `GCHAT_ERR_AUTH_EXPIRED` event callback so Go marks the bridge state `BAD_CREDENTIALS` and halts reconnects.

- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/gchat:gchat_ffi_test` to confirm green**
  Run: `bazel test //apps/desktop/courier/gchat:gchat_ffi_test`
  Expected: PASS.

- [ ] **Step 5: Commit Task 5**
  Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): implement Google Chat WebChannel streaming and UTF-16 ChunkParser" apps/desktop/courier/gchat`

---

### Task 6: Inbound UTF-16 `Annotation` & Bot-Card Converter (`src/fmt/mod.rs`, `src/fmt/inbound.rs`)

**Files:**
- Create: `apps/desktop/courier/gchat/src/fmt/mod.rs`
- Create: `apps/desktop/courier/gchat/src/fmt/inbound.rs`
- Modify: `apps/desktop/courier/gchat/src/lib.rs`
- Modify: `apps/desktop/courier/gchat/src/ffi.rs`

**Interfaces:**
```rust
// apps/desktop/courier/gchat/src/fmt/inbound.rs
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct ConvertedInboundText {
    pub body: String,
    pub formatted_body: Option<String>,
    pub mentions: Vec<String>, // Gaia IDs mentioned
    pub mention_all: bool,
}

pub fn annotations_to_matrix_html(
    text: &str,
    annotations: &[googlechat::Annotation],
    attachments: &[googlechat::Attachment],
) -> ConvertedInboundText;
```

- [ ] **Step 1: Write failing unit tests for inbound `Annotation` and bot-card conversion**
  In `src/fmt/inbound.rs`, write unit tests:
  - `test_inbound_annotations_convert_utf16_spans_with_emojis_and_nested_styles`:
    - Input text `"Hi 👋 bold italic strike code"` with `FormatMetadata` spans (`BOLD (1)`, `ITALIC (2)`, `STRIKE (3)`, `MONOSPACE (4)`, `MONOSPACE_BLOCK (6)`, `UNDERLINE (10)`, `FONT_COLOR (8)` with signed int32 color `((0xFF3366 | 0x7F000000) as i64 - (1 << 31)) as i32`), `LinkMetadata` (`URL`), and `UserMentionMetadata` (`UserId.id = "112233445566778899001"`).
    - Assert UTF-16 offsets after `"👋"` (2 UTF-16 units) align accurately and produce `<strong>`, `<em>`, `<del>`, `<code>`, `<pre><code>`, `<u>`, `<font color="#ff3366">`, `<a href="...">`, and pill link `<a href="https://matrix.to/#/@gchat_112233445566778899001:courier.local">`.
  - `test_inbound_annotations_clamp_or_skip_out_of_bounds_and_negative_offsets`:
    - Input `Annotation` with negative `start_index = -5`, `length = -1`, or `start_index + length > utf16_len` never panics; out-of-bounds spans are safely skipped/clamped via `checked_add`.
  - `test_inbound_bot_card_attachment_field_15_renders_structured_fallback`:
    - Input `Message` with empty `text_body` and an `Attachment` carrying `app_card` (field 15) with header title `"PagerDuty Alert"`, subtitle `"Sev-2"`, section widgets (`text_paragraph`, `decorated_text`, `button_list` with link `"https://example.com/inc/42"`).
    - Assert `annotations_to_matrix_html` renders structured blockquote/heading/link fallback HTML and plain-text summary so bot cards are never blank bubbles.

- [ ] **Step 2: Run `bazel test //apps/desktop/courier/gchat:gchat_ffi_test` to confirm failure**
  Run: `bazel test //apps/desktop/courier/gchat:gchat_ffi_test`
  Expected: FAIL.

- [ ] **Step 3: Implement `src/fmt/mod.rs`, `src/fmt/inbound.rs`, and wire `gchat_annotations_to_html` in `ffi.rs`**
  Implement UTF-16 slice conversion (`Vec<u16>` with `u32::try_from(start_index)` + `checked_add(length)`), RGB decoding (`u32::from_ne_bytes(color.to_ne_bytes()) & 0x00FF_FFFF`), HTML entity escaping on unannotated segments, tag opening/closing stack sorted by `(start, -end)`, and `Attachment` field 15 bot-card fallback rendering.

- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/gchat:gchat_ffi_test` to confirm green**
  Run: `bazel test //apps/desktop/courier/gchat:gchat_ffi_test`
  Expected: PASS.

- [ ] **Step 5: Commit Task 6**
  Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): add inbound Google Chat UTF-16 annotation and bot-card converter" apps/desktop/courier/gchat`

---

### Task 7: Go Conversation Sync (`paginated_world`, `list_topics`, `list_messages`, `catch_up_user`) & Live Remote Events

**Files:**
- Create: `apps/desktop/courier/engine/internal/gchat/sync.go`
- Modify: `apps/desktop/courier/engine/internal/gchat/client.go`
- Modify: `apps/desktop/courier/engine/internal/gchat/ffi.go`
- Modify: `apps/desktop/courier/engine/internal/gchat/gchat_test.go`

**Interfaces:**
```go
// Portal ID encoding in apps/desktop/courier/engine/internal/gchat/sync.go:
// - 1:1 DM or Group DM: networkid.PortalID("dm:" + dmID)
// - Named Space:        networkid.PortalID("space:" + spaceID)
// - Message ID:         networkid.MessageID(msgParentID + "/" + msgID)
// - Thread root ID:     networkid.MessageID(topicID + "/" + topicID)
// - User / Ghost ID:    networkid.UserID(gaiaID)
```

- [ ] **Step 1: Write failing Go tests for conversation list sync, single-page backfill, revision cursor separation, and live events**
  In `apps/desktop/courier/engine/internal/gchat/gchat_test.go`, write tests:
  - `TestPaginatedWorldSyncsDMsAndSpacesWithThreadedMetadata`:
    - Feeds synthetic `PaginatedWorldResponse` containing 1 DM (`DmId.dm_id = "dm_abc"`, `dm_memberships` with peer `"112233445566778899002"`) and 1 Space (`SpaceId.space_id = "space_xyz"`, `name = "Engineering"`, `topic_threaded = true`, `user_revision = 500`, `group_revision = 120`).
    - Asserts portals `dm:dm_abc` (`RoomTypeDM`) and `space:space_xyz` (`RoomTypeDefault`, portal metadata `TopicThreaded: true`) are created and `user_revision = 500` is stored separately from `space:space_xyz`'s `group_revision = 120`.
  - `TestBackfillUsesListTopicsForSpacesAndListMessagesForDMs`:
    - Asserts `FetchMessages` on `space:space_xyz` calls `/u/0/api/list_topics` (`page_size_for_topics = 30`, `page_size_for_replies = 10`) and on `dm:dm_abc` calls `/u/0/api/list_messages` (`page_size = 50`), doing a single-page fetch on demand without recursive archive crawling.
  - `TestCatchUpUserAdvancesUserRevisionWithoutOverwritingGroupRevision`:
    - Simulates a WebChannel reconnect triggering `/u/0/api/catch_up_user` with `from_revision = 500` and asserts `user_revision` updates to `response.read_revision` while per-portal `group_revision` cursors only advance on `/u/0/api/catch_up_group` or `Event.group_revision`.
  - `TestLiveWebChannelEventsMapMessagesReactionsEditsUnsendsReceiptsAndTyping`:
    - Feeds synthetic WebChannel `EventBody` payloads for:
      1. `MESSAGE_POSTED` (with `TopicId`, `SendReplyTarget` quote reply, and `Annotation`s),
      2. `MESSAGE_UPDATED` (edit),
      3. `MESSAGE_DELETED` (unsend),
      4. `REACTION_CREATED` / `REACTION_DELETED` (verifying `❤` without `U+FE0F` is normalized to `"❤️"` for Courier display),
      5. `GROUP_READ_STATE_UPDATED` (read receipt timestamp),
      6. `TYPING_STATE_CHANGED` (`STATE_TYPING` -> 6s typing notification),
      7. `MEMBERSHIP_CHANGED`.

- [ ] **Step 2: Run `bazel test //apps/desktop/courier/engine/internal/gchat:gchat_test` to confirm failure**
  Run: `bazel test //apps/desktop/courier/engine/internal/gchat:gchat_test`
  Expected: FAIL.

- [ ] **Step 3: Implement `apps/desktop/courier/engine/internal/gchat/sync.go`**
  Implement `syncWorld` (`POST /u/0/api/paginated_world` with `FetchOptions: [EXCLUDE_DYNAMIC_LITE, INCLUDE_SNIPPET, PARTICIPANT_NAMES]`), `FetchMessages` (`list_topics` vs `list_messages`), `catchUpAfterReconnect` (`catch_up_user` + `catch_up_group` keeping `user_revision` and `group_revision` strictly separated in portal/login metadata), and WebChannel event translation into `bridgev2.RemoteMessage`, `bridgev2.RemoteEdit`, `bridgev2.RemoteMessageRemove`, `bridgev2.RemoteReaction`, `bridgev2.RemoteReceipt`, `bridgev2.RemoteTyping`, and `bridgev2.RemoteChatInfoChange`.

- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/engine/internal/gchat:gchat_test` to confirm green**
  Run: `bazel test //apps/desktop/courier/engine/internal/gchat:gchat_test`
  Expected: PASS.

- [ ] **Step 5: Commit Task 7**
  Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): implement Google Chat conversation sync, backfill, and live event mapping" apps/desktop/courier/engine/internal/gchat`

---

## Milestone 3: Send Path

### Task 8: Outbound Matrix HTML to Google Chat UTF-16 `Annotation` Converter (`src/fmt/outbound.rs`)

**Files:**
- Create: `apps/desktop/courier/gchat/src/fmt/outbound.rs`
- Modify: `apps/desktop/courier/gchat/src/fmt/mod.rs`
- Modify: `apps/desktop/courier/gchat/src/ffi.rs`

**Interfaces:**
```rust
// apps/desktop/courier/gchat/src/fmt/outbound.rs
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct OutboundFormattedMessage {
    pub text: String,
    pub annotations: Vec<googlechat::Annotation>, // encoded or serde-represented
}

pub fn matrix_html_to_annotations(
    plain_body: &str,
    formatted_body: Option<&str>,
    mention_map: &std::collections::HashMap<String, String>, // display -> gaia_id
    allow_mention_all: bool,
) -> Result<(String, Vec<googlechat::Annotation>), GChatError>;
```

- [ ] **Step 1: Write failing unit tests for outbound HTML -> `Annotation` conversion in `src/fmt/outbound.rs`**
  Write unit tests covering every formatting rule in Spec §4.2 and §5:
  - `test_outbound_html_generates_utf16_annotations_for_all_supported_tags`:
    - Input HTML: `<p>Hello 🚀 <strong>bold</strong> <em>italic</em> <del>strike</del> <code>inline</code> <u>under</u> <font color="#ff3366">colored</font> <a href="https://example.com">link</a></p><pre><code>fn main() {}</code></pre><ul><li>item 1</li><li>item 2</li></ul>`
    - Assert output plain `text` has HTML tags stripped, bullet items prefixed with `"• "`, and `Annotation` entries with exact UTF-16 `start_index` and `length` after `"🚀"` (2 UTF-16 units) for `BOLD (1)`, `ITALIC (2)`, `STRIKE (3)`, `MONOSPACE (4)`, `MONOSPACE_BLOCK (6)`, `UNDERLINE (10)`, `FONT_COLOR (8)` with signed int32 `((0xFF3366 | 0x7F000000) as i64 - (1 << 31)) as i32`, and `LINK_DATA (6)`.
  - `test_outbound_mentions_emit_user_mention_and_mention_all_annotations`:
    - Input with `<a href="https://matrix.to/#/@gchat_112233445566778899002:courier.local">@Grace Hopper</a>` and `@all` (when `allow_mention_all == true`) emits `USER_MENTION (1)` with `UserMentionMetadata { id: UserId("112233445566778899002"), type: MENTION (1) }` and `UserMentionMetadata { type: MENTION_ALL (2) }`.
    - When `allow_mention_all == false` (in a 1:1 DM), `@all` is left as plain text without a `MENTION_ALL` annotation.
  - `test_outbound_unsupported_blockquote_and_headings_degrade_to_plain_text`:
    - `<blockquote>quote</blockquote>` becomes `"> quote\n"` and `<h1>Title</h1>` becomes `BOLD` annotation on `"Title"`.

- [ ] **Step 2: Run `bazel test //apps/desktop/courier/gchat:gchat_ffi_test` to confirm failure**
  Run: `bazel test //apps/desktop/courier/gchat:gchat_ffi_test`
  Expected: FAIL.

- [ ] **Step 3: Implement `src/fmt/outbound.rs` and wire `gchat_html_to_annotations` in `ffi.rs`**
  Implement HTML walking, UTF-16 code-unit accumulator, RGB signed bitmask encoding `((rgb & 0x00FF_FFFF) | 0x7F00_0000) as i32`, bullet list prefixing, mention pill extraction, and round-trip consistency with `annotations_to_matrix_html`.

- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/gchat:gchat_ffi_test` to confirm green**
  Run: `bazel test //apps/desktop/courier/gchat:gchat_ffi_test`
  Expected: PASS.

- [ ] **Step 5: Commit Task 8**
  Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): add outbound Matrix HTML to Google Chat UTF-16 annotation converter" apps/desktop/courier/gchat`

---

### Task 9: Outbound Message Actions (`create_topic`, `create_message`, Replies, Threads, Edits, Unsends, Reactions, Receipts, Typing) & Capability Table Wiring

**Files:**
- Create: `apps/desktop/courier/engine/internal/gchat/send.go`
- Modify: `apps/desktop/courier/engine/internal/gchat/client.go`
- Modify: `apps/desktop/courier/engine/internal/gchat/gchat_test.go`
- Modify: `apps/desktop/courier/engine/internal/actions/features.go`
- Modify: `apps/desktop/courier/engine/internal/networks/networks_test.go`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/ChatFeaturesTests.swift`

**Interfaces:**
```go
// apps/desktop/courier/engine/internal/gchat/send.go
func (c *GChatClient) GetCapabilities(ctx context.Context, portal *bridgev2.Portal) *event.RoomFeatures
func (c *GChatClient) HandleMatrixMessage(ctx context.Context, msg *bridgev2.MatrixMessage) (*bridgev2.MatrixMessageResponse, error)
func (c *GChatClient) HandleMatrixEdit(ctx context.Context, msg *bridgev2.MatrixEdit) error
func (c *GChatClient) HandleMatrixMessageRemove(ctx context.Context, msg *bridgev2.MatrixMessageRemove) error
func (c *GChatClient) HandleMatrixReaction(ctx context.Context, msg *bridgev2.MatrixReaction) (reactionInfo any, err error)
func (c *GChatClient) HandleMatrixReactionRemove(ctx context.Context, msg *bridgev2.MatrixReactionRemove) error
func (c *GChatClient) HandleMatrixReadReceipt(ctx context.Context, receipt *bridgev2.MatrixReadReceipt) error
func (c *GChatClient) HandleMatrixTyping(ctx context.Context, typing *bridgev2.MatrixTyping) error
```

- [ ] **Step 1: Write failing tests in `gchat_test.go`, `networks_test.go`, and `ChatFeaturesTests.swift`**
  - In `apps/desktop/courier/engine/internal/gchat/gchat_test.go`, write:
    - `TestSendNewTopicInThreadedSpaceAndCreateMessageInThreadOrDM`:
      - Top-level message in threaded space (`topic_threaded == true`) calls `POST /u/0/api/create_topic` with `local_id = "mautrix-googlechat%<uuid>"`, `retention_settings.state = DEFAULT_AWAKE (1)`.
      - Thread reply in threaded space or message in DM calls `POST /u/0/api/create_message` with `MessageParentId.topic_id` and `local_id`.
      - Inline quote-reply sets `SendReplyTarget { message_id, create_time }` where `create_time` is loaded from stored `MessageMetadata.CreateTimeMicros`.
      - Receiving the WebChannel echo with matching `local_id` deduplicates against the pending outbound send.
    - `TestSendEditUnsendReactionReceiptAndTyping`:
      - `HandleMatrixEdit` calls `POST /u/0/api/edit_message`.
      - `HandleMatrixMessageRemove` calls `POST /u/0/api/delete_message`.
      - `HandleMatrixReaction` strips `U+FE0F` (`"❤️"` -> `"❤"`) before calling `POST /u/0/api/update_reaction` with `ReactionAction = ADD (1)`.
      - `HandleMatrixReadReceipt` calls `POST /u/0/api/mark_group_readstate` with microsecond timestamp.
      - `HandleMatrixTyping` calls `POST /u/0/api/set_typing_state` (`STATE_TYPING (1)` / `STATE_STOPPED (2)`).
  - In `apps/desktop/courier/engine/internal/networks/networks_test.go`, add `"gchat"` expectations to `platformActionRows()` and `platformReceiptColumns()`.
  - In `apps/desktop/courier/app/Tests/CourierCoreTests/ChatFeaturesTests.swift`, add `testGoogleChatRoomFeaturesToggleThreadAndMentionRoomByRoomType`.

- [ ] **Step 2: Run tests to confirm failure**
  Run: `bazel test //apps/desktop/courier/engine/internal/gchat:gchat_test //apps/desktop/courier/engine/internal/networks:networks_test //apps/desktop/courier/app:CourierCoreTests`
  Expected: FAIL.

- [ ] **Step 3: Implement `send.go` and update `actions/features.go`**
  - Implement `GetCapabilities` on `GChatClient` returning static capabilities from the Capability Table (`MaxTextLength: 4096`, `Reply: true`, `Thread: true`, `Edit: true`, `Unsend: true`, `ReactionCount: -1`, `ReadReceipts: true`, `TypingNotifications: true`, `Formatting` map, `MentionRoom: true`, and `File` map with `MaxSize: 200 * 1024 * 1024`) plus dynamic per-portal overrides (`Thread: false` when `!portalMeta.TopicThreaded`, `MentionRoom: false` when `portal.RoomType == database.RoomTypeDM`).
  - In `apps/desktop/courier/engine/internal/actions/features.go`, update `networkFileCeiling(network string)` so `"gchat"` returns `200 * 1024 * 1024` (200 MiB) instead of clamping to 100 MiB, and add `"gchat": true` to `groupDeleteNeedsEveryone`.
  - Implement `HandleMatrixMessage`, `HandleMatrixEdit`, `HandleMatrixMessageRemove`, `HandleMatrixReaction`, `HandleMatrixReactionRemove`, `HandleMatrixReadReceipt`, and `HandleMatrixTyping`.

- [ ] **Step 4: Re-run Go and Swift tests to confirm green**
  Run: `bazel test //apps/desktop/courier/engine/internal/gchat:gchat_test //apps/desktop/courier/engine/internal/networks:networks_test //apps/desktop/courier/app:CourierCoreTests`
  Expected: PASS.

- [ ] **Step 5: Commit Task 9**
  Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): implement Google Chat send path, reactions, receipts, typing, and capability table" apps/desktop/courier/engine/internal/gchat apps/desktop/courier/engine/internal/actions/features.go apps/desktop/courier/engine/internal/networks/networks_test.go apps/desktop/courier/app/Tests/CourierCoreTests/ChatFeaturesTests.swift`

---

## Milestone 4: Media

### Task 10: SSRF Guard (`src/netguard.rs`), Scotty 2-Step Uploader, Attachment & Avatar Downloader (`src/media.rs`), & Go Media Plumbing (`media.go`)

**Files:**
- Modify: `apps/desktop/courier/gchat/src/netguard.rs`
- Create: `apps/desktop/courier/gchat/src/media.rs`
- Modify: `apps/desktop/courier/gchat/src/lib.rs`
- Modify: `apps/desktop/courier/gchat/src/ffi.rs`
- Create: `apps/desktop/courier/engine/internal/gchat/media.go`
- Modify: `apps/desktop/courier/engine/internal/gchat/send.go`
- Modify: `apps/desktop/courier/engine/internal/gchat/sync.go`
- Modify: `apps/desktop/courier/engine/internal/gchat/gchat_test.go`

**Interfaces:**
```rust
// apps/desktop/courier/gchat/src/netguard.rs
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EndpointRole {
    ChatRpcAndUpload,       // chat.google.com, mail.google.com/chat
    AuthenticatedAttachment,// chat.google.com, mail.google.com, *.googleusercontent.com, *.ggpht.com, docs.google.com, drive.google.com
    AvatarHost,             // *.googleusercontent.com, *.ggpht.com
    ExternalPublicImage,    // HTTPS-only, non-private IP, no cookies
}

pub fn is_globally_routable_ip(ip: std::net::IpAddr) -> bool;
pub fn validate_url_for_role(url: &url::Url, role: EndpointRole, allow_loopback_test: bool) -> Result<(), GChatError>;
```

```rust
// apps/desktop/courier/gchat/src/media.rs
pub const MAX_MEDIA_BYTES: usize = 200 * 1024 * 1024; // 200 MB
pub const MAX_AVATAR_OR_EXTERNAL_BYTES: usize = 20 * 1024 * 1024; // 20 MB
pub const MAX_REDIRECT_HOPS: usize = 10;

pub async fn scotty_upload(
    client: &GChatClient,
    raw_group_id: &str,
    filename: &str,
    content_type: &str,
    data: &[u8],
) -> Result<googlechat::UploadMetadata, GChatError>;

pub async fn download_attachment(
    client: &GChatClient,
    attachment_token: &str,
) -> Result<(Vec<u8>, String), GChatError>;
```

- [ ] **Step 1: Write failing unit tests for SSRF IPv4/IPv6 unwrapping, Scotty 2-step upload, redirect-checked attachment download, and multi-attachment ordering**
  - In `src/netguard.rs`, write `test_ssrf_guard_rejects_private_and_embedded_ipv6_addresses`:
    - Assert `is_globally_routable_ip` rejects `127.0.0.1`, `10.0.0.1`, `172.16.0.1`, `192.168.1.1`, `100.64.0.1` (CGNAT), `169.254.169.254` (cloud metadata), `0.0.0.0`, `::1`, `fe80::1`, `fc00::1`, `fd12:3456::1`, IPv4-mapped `::ffff:127.0.0.1` and `::ffff:169.254.169.254`, IPv4-compatible `::10.0.0.1`, 6to4 `2002:7f00:0001::1` (`127.0.0.1`), NAT64 `64:ff9b::a00:1` (`10.0.0.1`) and `64:ff9b:1::c0a8:101` (`192.168.1.1`), Teredo `2001:0000:4136:e378:8000:63bf:f5ff:fefe` (inverted `10.0.1.1`), and ISATAP `fe80::200:5efe:10.0.0.1`.
    - Assert `validate_url_for_role` rejects `http://` schemes, rejects non-Google hosts for `ChatRpcAndUpload`, and rejects `x-goog-upload-url` values pointing outside `https://chat.google.com/` or `https://mail.google.com/chat/`.
  - In `src/media.rs`, write `test_scotty_two_step_upload_and_redirect_download_strip_cookies_on_cdn`:
    - Against a local loopback test server (`AllowLoopbackForTest`):
      - Step 1: `POST /u/0/uploads?group_id=space_xyz` with `X-Goog-Upload-Command: start`, `X-Goog-Upload-Protocol: resumable`, `X-Goog-Upload-Header-Content-Length`, `X-Goog-Upload-Header-Content-Type`, and body `FileMetadata` JSON returns `x-goog-upload-url`.
      - Step 2: `PUT <x-goog-upload-url>` with `X-Goog-Upload-Command: upload, finalize` and `X-Goog-Upload-Offset: 0` returns base64-encoded `ComGoogleRtcMeetingsV1UploadMetadata` and extracts `UploadMetadata` (field 1).
      - Download: `GET /u/0/api/get_attachment_url?alt=proto&attachment_token=tok_1` returns `download_url` redirecting to simulated CDN endpoint; asserts the CDN hop receives **no** `Cookie` or `x-framework-xsrf-token` header and streams up to 200 MB.
  - In `apps/desktop/courier/engine/internal/gchat/gchat_test.go`, write `TestMultiAttachmentInboundUsesZeroPaddedPartIDsAndOutboundUploadsViaScotty`:
    - Inbound `Message` with text + 2 attachments produces `ConvertedMessage.Parts` with IDs `""` (text), `"att_0000"`, and `"att_0001"` (`fmt.Sprintf("att_%04d", i)`).

- [ ] **Step 2: Run Rust and Go tests to confirm failure**
  Run: `bazel test //apps/desktop/courier/gchat:gchat_ffi_test //apps/desktop/courier/engine/internal/gchat:gchat_test`
  Expected: FAIL.

- [ ] **Step 3: Implement `src/netguard.rs`, `src/media.rs`, `ffi.rs` media entrypoints, and `engine/internal/gchat/media.go`**
  - Implement `is_globally_routable_ip` (unwrapping IPv4-mapped, IPv4-compatible, 6to4, NAT64 `64:ff9b::/96` & `64:ff9b:1::/48`, Teredo bitwise-inverted last 32 bits, and ISATAP `:5efe:`/`:0200:5efe:` last 32 bits before checking IPv4 private/loopback/CGNAT/link-local ranges), `ReqwestDnsResolver` re-validating every resolved socket address at connect time, `.no_proxy()`, and redirect policy (`Policy::custom`) validating every hop up to 10 hops.
  - Implement `scotty_upload`, `download_attachment`, `download_avatar`, and gated external URL fetching (`download_external_image_if_enabled`, off by default).
  - Implement `apps/desktop/courier/engine/internal/gchat/media.go` handling outbound media (`MsgImage`, `MsgVideo`, `MsgAudio`, `CapMsgVoice`, `MsgFile`, `CapMsgGIF` up to 200 MB) and inbound multi-attachment extraction (`att_%04d`).

- [ ] **Step 4: Re-run Rust and Go tests to confirm green**
  Run: `bazel test //apps/desktop/courier/gchat:gchat_ffi_test //apps/desktop/courier/engine/internal/gchat:gchat_test`
  Expected: PASS.

- [ ] **Step 5: Commit Task 10**
  Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): add Google Chat Scotty media upload/download and SSRF guard" apps/desktop/courier/gchat apps/desktop/courier/engine/internal/gchat`

---

## Milestone 5: Polish & By-Hand Verification

### Task 11: Chat & Space Management (`create_dm`, `hide_group`, `update_group` Preserving `guidelines`, Mute Sync, Membership)

**Files:**
- Create: `apps/desktop/courier/engine/internal/gchat/rooms.go`
- Modify: `apps/desktop/courier/engine/internal/gchat/client.go`
- Modify: `apps/desktop/courier/engine/internal/gchat/gchat_test.go`
- Modify: `apps/desktop/courier/engine/internal/networks/networks_test.go`

**Interfaces:**
```go
// apps/desktop/courier/engine/internal/gchat/rooms.go
var (
	_ bridgev2.IdentifierResolvingNetworkAPI = (*GChatClient)(nil)
	_ bridgev2.GhostDMCreatingNetworkAPI     = (*GChatClient)(nil)
	_ actions.MuteHandlingNetworkAPI         = (*GChatClient)(nil)
	_ actions.GroupNamingNetworkAPI          = (*GChatClient)(nil)
	_ actions.GroupTopicNetworkAPI           = (*GChatClient)(nil)
	_ actions.GroupMembershipNetworkAPI      = (*GChatClient)(nil)
	_ actions.ChatDeletingNetworkAPI         = (*GChatClient)(nil)
)
```

- [ ] **Step 1: Write failing tests in `gchat_test.go` and `networks_test.go` for chat/space management**
  - In `apps/desktop/courier/engine/internal/gchat/gchat_test.go`, write:
    - `TestResolveIdentifierAndCreateDMByGaiaIDOrEmail`:
      - `ResolveIdentifier` accepts a 21-digit Gaia ID (`"112233445566778899002"`) or email address (`"grace@example.com"`), calls `POST /u/0/api/create_dm`, and `CreateChatWithGhost` returns the `dm:<dm_id>` portal.
    - `TestSetChatNameAndSetChatTopicPreservesSpaceGuidelines`:
      - `SetChatName` calls `POST /u/0/api/update_group` with `Mask = [NAME (1)]`.
      - `SetChatTopic` first fetches `get_group` to read existing `space_details.guidelines`, then calls `POST /u/0/api/update_group` with `Mask = [SPACE_DETAILS (4)]` and `SpaceDetails { description: newTopic, guidelines: existingGuidelines }`, proving `guidelines` is never wiped out.
    - `TestMuteSyncAndMembershipAndHideGroup`:
      - `HandleMute(ctx, portal, -1)` (mute) calls `POST /u/0/api/update_group_notification_settings` with `NotificationState = MUTED (3)` and `Mask = [NOTIFICATION_STATE (1)]`; unmute (`0`) sends `NOTIFY_ALWAYS (1)`.
      - `AddChatMember` calls `POST /u/0/api/create_membership` with `MembershipState = MEMBER_INVITED (1)` and `MembershipRole = ROLE_MEMBER (2)`.
      - `RemoveChatMember` calls `POST /u/0/api/remove_memberships` (and for self in a space, leaves the space).
      - `DeleteChat` on a DM calls `POST /u/0/api/hide_group` with `hide = true`.
  - In `apps/desktop/courier/engine/internal/networks/networks_test.go`, add `"gchat"` to `platformClients()` (`sent: ["mute"]`, `implements: ["mute"]`) and `TestGroupAndChatManagementTableMatchesTheBridges` (`SetName: true, SetTopic: true, SetAvatar: false, Membership: true, PowerLevels: false, DeleteChat: true`). Confirm `GChatClient` does **not** implement `GroupCreatingNetworkAPI` (`CreateGroup` stays hidden in UI per Spec §4.1 & §13).

- [ ] **Step 2: Run tests to confirm failure**
  Run: `bazel test //apps/desktop/courier/engine/internal/gchat:gchat_test //apps/desktop/courier/engine/internal/networks:networks_test`
  Expected: FAIL.

- [ ] **Step 3: Implement `apps/desktop/courier/engine/internal/gchat/rooms.go`**
  Implement `ResolveIdentifier`, `CreateChatWithGhost`, `HandleMute`, `SetChatName`, `SetChatTopic` (reading current `space_details.guidelines` before sending `Mask = [SPACE_DETAILS (4)]`), `AddChatMember`, `RemoveChatMember`, and `DeleteChat`.

- [ ] **Step 4: Re-run tests to confirm green**
  Run: `bazel test //apps/desktop/courier/engine/internal/gchat:gchat_test //apps/desktop/courier/engine/internal/networks:networks_test`
  Expected: PASS.

- [ ] **Step 5: Commit Task 11**
  Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): implement Google Chat DM creation, mute sync, space details, and membership" apps/desktop/courier/engine/internal/gchat apps/desktop/courier/engine/internal/networks/networks_test.go`

---

### Task 12: Fuzz Targets, `logscrub` End-to-End Redaction, & Owner's By-Hand Verification Day Checklist

**Files:**
- Create: `apps/desktop/courier/gchat/src/fuzz_tests.rs`
- Modify: `apps/desktop/courier/gchat/src/lib.rs`
- Modify: `apps/desktop/courier/engine/internal/logscrub/logscrub.go`
- Modify: `apps/desktop/courier/engine/internal/logscrub/bridge_test.go`
- Create: `apps/desktop/courier/engine/docs/gchat-by-hand.md`

**Interfaces:**
```rust
// apps/desktop/courier/gchat/src/fuzz_tests.rs
pub fn fuzz_chunk_parser_once(data: &[u8]);
pub fn fuzz_pblite_event_once(data: &[u8]);
pub fn fuzz_fmt_annotations_once(text: &str, raw_annotations_proto: &[u8]);
```

- [ ] **Step 1: Write failing tests for fuzz harnesses and `logscrub` PII redaction**
  - In `apps/desktop/courier/gchat/src/fuzz_tests.rs`, write deterministic corpus + PRNG seed sweeps exercising:
    - `fuzz_chunk_parser`: arbitrary byte slices, invalid UTF-8 sequences, split 4-byte emojis, negative/huge length headers, and multi-megabyte claims never panic or allocate unbounded memory.
    - `fuzz_pblite_event`: arbitrary nested JSON arrays/objects up to and beyond depth 64 decoded against `googlechat.WebChannelEvent` and `googlechat.Event` never panic.
    - `fuzz_fmt_annotations`: arbitrary text strings paired with arbitrary `Annotation` `start_index` / `length` / `type` values never panic on UTF-16 slicing.
  - In `apps/desktop/courier/engine/internal/logscrub/bridge_test.go`, add `TestLogscrubRedactsGoogleChatCookiesTokensGaiaIDsAndWebChannelURLs`:
    - Feeds log lines containing `COMPASS=chat=secret_compass; OSID=secret_osid; SID=secret_sid`, `"xsrf_token":"AF1QipP_secret"`, Gaia ID `user_id="112233445566778899001"`, email `ada.lovelace@example.com`, and `UnexpectedStatusError: GET https://chat.google.com/u/0/webchannel/events_encoded?gsessionid=abc&SID=sid_secret&AID=42&CI=0&TYPE=xmlhttp: 400 Bad Request`.
    - Asserts `logscrub` redacts the cookies, XSRF token, Gaia ID, email, and strips the query parameters from the WebChannel URL.

- [ ] **Step 2: Run Rust and Go tests to confirm failure**
  Run: `bazel test //apps/desktop/courier/gchat:gchat_ffi_test //apps/desktop/courier/engine/internal/logscrub:logscrub_test`
  Expected: FAIL.

- [ ] **Step 3: Implement `src/fuzz_tests.rs`, update `logscrub.go`, and write `apps/desktop/courier/engine/docs/gchat-by-hand.md`**
  - Implement `src/fuzz_tests.rs` and wire into `gchat_ffi_test`.
  - Update `apps/desktop/courier/engine/internal/logscrub/logscrub.go` to scrub `COMPASS=`, `OSID=`, `SID=`, `HSID=`, `SSID=`, `APISID=`, `SAPISID=`, `__Secure-1PSID=`, `__Secure-3PSID=`, `xsrf_token`, 21-digit Gaia IDs in user/ghost contexts, and WebChannel query strings (`gsessionid=`, `SID=`).
  - Write `apps/desktop/courier/engine/docs/gchat-by-hand.md` with the Owner's By-Hand Verification Day runbook:
    1. Build and install Courier (`bazel run --config=macos-app //apps/desktop/courier/app:install`).
    2. Add Network ▸ **Google Chat** ▸ verify `WKWebView` opens `https://chat.google.com/`, completes Google sign-in + 2FA, captures `COMPASS`, `OSID`, `SID`, `HSID`, `SSID`, closes automatically, and displays account as `Name (email)`.
    3. Verify initial conversation list sync (`paginated_world`) populates DMs and named spaces with avatars and unread state.
    4. Open a DM and a threaded space; scroll up to verify single-page backfill (`list_messages` and `list_topics`).
    5. Send and receive plain text, bold/italic/strikethrough/code/pre/bullet/link formatting, `@user` and `@all` mentions, inline quote-replies, and space thread replies; verify `local_id` deduplication prevents duplicate bubbles.
    6. Add and remove emoji reactions (including `"❤️"` with `U+FE0F` normalization), edit a sent message, and unsend a message in both directions.
    7. Upload and download an image, a voice note/audio file, and a general file attachment via Scotty.
    8. Verify read receipts and 6-second typing indicator in both directions.
    9. Toggle mute/unmute on a chat, rename a space, update a space description (verifying existing space guidelines remain intact in the Google Chat web client), and start a new DM by email address.
    10. Put the Mac to sleep for >2 minutes, wake it, and verify WebChannel reconnects and runs `catch_up_user` / `catch_up_group` without missing messages sent while asleep.
    11. Inspect `~/Library/Logs/Courier/` and confirm zero cookie values, XSRF tokens, Gaia IDs, emails, or message bodies appear in the scrubbed logs.

- [ ] **Step 4: Run the full verification suite for `gchat`, `networks`, `actions`, `logscrub`, and `CourierCoreTests`**
  Run: `bazel test //apps/desktop/courier/gchat/... //apps/desktop/courier/engine/internal/gchat/... //apps/desktop/courier/engine/internal/networks/... //apps/desktop/courier/engine/internal/actions/... //apps/desktop/courier/engine/internal/logscrub/... //apps/desktop/courier/app:CourierCoreTests`
  Expected: ALL PASS (including `offline_test` confirming zero external network calls).

- [ ] **Step 5: Commit Task 12**
  Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): add Google Chat fuzz harnesses, logscrub rules, and by-hand verification guide" apps/desktop/courier/gchat apps/desktop/courier/engine/internal/logscrub apps/desktop/courier/engine/docs/gchat-by-hand.md`
