# Src

## Overview
Component package providing implementation for `apps/embedded/vitruvian-deck/src`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [cloud_ci.cpp:201]: `HTTPClient http;`
- [cloud_ci.cpp:202]: `http.setUserAgent("Vitruvian-Deck");`
- [cloud_ci.cpp:203]: `http.setConnectTimeout(10000);`
- [cloud_ci.h:32]: `// The HTTPS fetch runs on its own FreeRTOS task -- a TLS handshake blocks for`
- [main.cpp:326]: `// Wireless radio state machines (portal HTTP serving, station reconnect,`
- [ota_manager.cpp:74]: `// HTTP `/update` endpoint`
- [ota_manager.cpp:302]: `Serial.printf("[OTA] Ready: http://%s/update (user %s) and %s.local:3232\n",`
- [ota_manager.h:29]: `//   2. An HTTP `/update` form on port 80 -- drag a .bin onto the page from any`
- [ota_manager.h:32]: `// Both are HTTP-Basic / OTA-password gated with the same device-derived`
- [wifi_manager.cpp:39]: `// Base portal window; every HTTP request re-arms it so the user is never cut`

## Verification
- Run: `bazel test //apps/embedded/vitruvian-deck/src/...`
