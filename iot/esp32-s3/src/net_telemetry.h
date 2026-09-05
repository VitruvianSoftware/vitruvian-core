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
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "version.h"

// ---------------------------------------------------------------------------
// Untethered telemetry transport: a UDP listener on NET_TELEMETRY_PORT (8266)
// carrying exactly the same newline-framed JSON as the USB CDC link, so the
// packet router upstream cannot tell the two channels apart (docs/protocol.md).
//
// UDP rather than TCP: the stream is lossy-tolerant 1 Hz telemetry, and a
// connectionless socket means a sleeping or re-IP'd Mac never leaves the
// firmware blocked in a half-open connection.
// ---------------------------------------------------------------------------

// Datagrams larger than this are truncated and counted as drops; the largest
// real packet (a six-button app profile) is well under 700 bytes.
#define NET_TELEMETRY_MAX_PACKET 1024

// Invoked from net_telemetry_loop() -- i.e. main-loop context, so the handler
// may touch LVGL. One call per newline-framed object in the datagram.
typedef void (*net_packet_cb_t)(const char* json, size_t len);

void net_telemetry_init(net_packet_cb_t cb);

// Bind/release the socket. Both are idempotent, so the caller can drive them
// straight off the Wi-Fi link state every loop iteration.
bool net_telemetry_start();
void net_telemetry_stop();
bool net_telemetry_is_listening();

void net_telemetry_loop();

// Sends one newline-framed JSON line back to the host that most recently sent
// us a packet. Returns false when no host has been seen yet (or the socket is
// down) -- the caller then falls back to USB CDC.
bool net_telemetry_send_line(const char* json);

bool net_telemetry_has_client();
const char* net_telemetry_client_ip();
uint16_t net_telemetry_client_port();

// millis() timestamp of the last accepted packet; 0 if none since boot.
unsigned long net_telemetry_last_rx_ms();

// Diagnostics surfaced by the [NET] log line and the tests' wire model.
uint32_t net_telemetry_rx_count();
uint32_t net_telemetry_drop_count();
