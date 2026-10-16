# Beeper Desktop Reference Extraction (`v4.3.209`)

This directory contains the complete static extraction and REA (`reverse-engineer-anything`) Evidence corpus for **Beeper Desktop (`BeeperTexts` v4.3.209)** from `/Applications/Beeper Desktop.app/Contents/Resources/app.asar` (`sha256: 163927f184b316909bc04bf4b0c76fd4ff360b6783a19680d7bbb067d12c0c4b`).

> **Branch Policy:** Keep this directory on the dedicated `feat/beeper-reference-extraction` reference branch for architecture planning and clean-room reconstruction. Do **not** merge raw extracted third-party bundles into `main`.

---

## Directory Layout

| Path | Description |
|---|---|
| `extracted-asar/` | 475 extracted & Prettier-formatted source, manifest, HTML, CSS, and JS/MJS module chunks from `app.asar` and `app.asar.unpacked` |
| `asar-header-manifest.json` | Complete raw ASAR virtual filesystem tree with byte offsets, sizes, and SHA-256 integrity records |
| `unpacked-and-binary-manifest.json` | Inventory of all 72 `app.asar.unpacked` native binaries/addons and 67 skipped binary media/WASM assets |
| `native-interfaces-summary.json` | Condensed Mach-O slices, linked frameworks, exports, and imports for `beeper_client_sdk_napi_binding.node`, `IMessage.node`, and `TextsSwift.node` |
| `rea-evidence/` | Canonical REA Evidence JSON records covering the 235-file AST/semantic analysis (`ev_0a18b5ff296c2501328476fe7bd16a790f14ba4d3e81f3624eff788aabca8f53`) and Mach-O binary inspections |

---

## Subsystem Map for Self-Hosted Reconstruction

### 1. Main Process & Local MCP / HTTP Server (`extracted-asar/build/main/`)
- `index.mjs` / `main-entry-CnfqTXzU.mjs` / `electron-before-ready-BIYuVIr8.mjs`: Electron bootstrap, custom protocol registration, and window lifecycle.
- `http-server-yJjafArR.mjs` / `app-api-NqP9XGk0.mjs` / `openapi-BK7IyLMq.mjs`: Built-in local HTTP control plane and Beeper Desktop API.
- `streamableHttp-C2-F8Eo0.mjs` / `sse-l3DRQviM.mjs`: Built-in MCP server transports (Streamable HTTP and SSE).
- `ipc-main-shim-DE4RL508.mjs` / `remote-method-Dje_9VSb.mjs`: Main-process RPC/IPC bridge to renderer windows.
- `AsyncSqlite-CpInlfQ-.mjs` / `sqlite-worker-BYmkyVxU.mjs`: Local SQLite persistence worker (`better-sqlite3`).
- `platform-worker-BjTfLpXw.mjs`: Texts/Beeper local platform bridge worker thread (drives local `IMessage.node` and `SimpleTwitterClient-BlyQEWJV.mjs`).
- `macos-contacts-server-D9gt4gn9.mjs` / `Keychain-CHHka2u7.mjs`: macOS Contacts (`ContactsServer`) and Keychain (`keytar`) integrations.

### 2. Preload Boundary (`extracted-asar/build/preload/`)
- `index.js`: `contextBridge` API exposed to renderer windows.

### 3. Renderer & Matrix Client Integration (`extracted-asar/build/renderer/` & `build-browser/`)
- `App-CsJiApxN.js`: Primary React unified inbox UI.
- `load-stores-B_4F31ws.js` / `main-process-state-wkFhis-C.js`: Client state stores and main-process state synchronization.
- `matrix-util-Cr_UwXbj.js` / `client-CsqrubtG.js` / `auths-BR-CCtaL.js`: Matrix sliding-sync, room/event normalization, and `@beeper/beeper-client-sdk` bindings.
- `AddAccountsBrowserWindow-C8cORiKR.js` / `LoginBrowserWindow-BmVwY1n-.js` / `Onboarding-C0fRuBrF.js`: Bridge connection and login flows.

### 4. Native Binaries (`rea-evidence/macho-*.json`)
- `beeper_client_sdk_napi_binding.node` (`ev_` in `macho-beeper_client_sdk_napi_binding.node.json`): N-API Rust binding over `matrix-rust-sdk`.
- `IMessage.node` (`rea-evidence/macho-IMessage.node.json`): Local macOS iMessage bridge addon.
- `TextsSwift.node` (`rea-evidence/macho-TextsSwift.node.json`): Swift N-API bridge (`NodeAPI.framework`).
