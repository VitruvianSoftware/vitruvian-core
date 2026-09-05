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

// ---------------------------------------------------------------------------
// Dual-channel packet router.
//
// One decoder for the newline-framed JSON wire protocol (docs/protocol.md),
// shared verbatim by the USB CDC link and the Wi-Fi UDP listener: a packet is
// handled identically whichever transport carried it. The router also owns
// link arbitration (which channel is "live" right now) and outbound command
// delivery, so a touch action reaches the Mac over whichever channel is up.
// ---------------------------------------------------------------------------

enum LinkChannel {
    LINK_CHANNEL_NONE = 0,  // nothing has been heard recently -> standby
    LINK_CHANNEL_USB,       // TinyUSB CDC serial (tethered)
    LINK_CHANNEL_NET        // UDP on NET_TELEMETRY_PORT (untethered LAN)
};

// A channel counts as live for this long after its last accepted packet.
#define LINK_ACTIVE_WINDOW_MS 3000UL

// Handles one JSON object. Returns true if it matched a known packet type.
// Must be called from main-loop context: the handlers touch LVGL.
bool packet_router_handle(const char* json, size_t len, LinkChannel channel);

// USB wins while it is live -- the cable is the lower-latency, always-powered
// path -- and Wi-Fi takes over the moment it goes quiet.
LinkChannel packet_router_active_channel();

unsigned long packet_router_last_usb_rx_ms();
unsigned long packet_router_last_net_rx_ms();

// True when a host daemon (either channel) has been heard within `within_ms`.
// The cloud poller uses this to stay out of the way while the Mac is driving.
bool packet_router_host_active(unsigned long within_ms);

// Emits one newline-framed JSON line to the host over the active channel,
// preferring UDP when the device is untethered and falling back to USB CDC.
// Returns the channel actually used.
LinkChannel packet_router_emit(const char* json);

// Device -> host radio telemetry, emitted over whichever channel is up.
void packet_router_send_wifi_status();
void packet_router_send_ble_status();
