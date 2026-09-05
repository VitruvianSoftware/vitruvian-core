// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#pragma once

// Compiled-in firmware version, surfaced in the mDNS TXT record and the
// /update OTA page. Bumped automatically by release-please (the annotation
// below is the generic-updater marker; see release-please-config.json's
// extra-files entry), so it never drifts from the released tag.
#define FIRMWARE_VERSION "0.1.7"  // x-release-please-version

// mDNS identity. `MDNS.begin(MDNS_HOSTNAME)` publishes
// "vitruvian-companion.local"; the service is what the Mac companion browses
// for when it has no --wifi-host pinned.
#define MDNS_HOSTNAME     "vitruvian-companion"
#define MDNS_SERVICE      "vitruvian"
#define MDNS_PROTO        "tcp"

// Single port for the untethered link: the UDP telemetry listener binds it,
// and the mDNS service advertises it.
#define NET_TELEMETRY_PORT 8266
