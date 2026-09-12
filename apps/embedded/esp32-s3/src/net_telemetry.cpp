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

#include "net_telemetry.h"

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiUdp.h>

static WiFiUDP udp;
static net_packet_cb_t packet_cb = NULL;

static bool listening = false;
static IPAddress client_ip;
static uint16_t client_port = 0;
static bool have_client = false;
static char client_ip_str[16] = "";

static unsigned long last_rx_ms = 0;
static uint32_t rx_count = 0;
static uint32_t drop_count = 0;

// +1 so the payload is always NUL-terminatable in place.
static char rx_buf[NET_TELEMETRY_MAX_PACKET + 1];

void net_telemetry_init(net_packet_cb_t cb) {
    packet_cb = cb;
}

bool net_telemetry_start() {
    if (listening) return true;
    if (WiFi.status() != WL_CONNECTED) return false;

    if (!udp.begin(NET_TELEMETRY_PORT)) {
        Serial.printf("[NET] UDP bind on :%d failed\n", NET_TELEMETRY_PORT);
        return false;
    }
    listening = true;
    Serial.printf("[NET] Telemetry listener up on %s:%d\n",
                  WiFi.localIP().toString().c_str(), NET_TELEMETRY_PORT);
    return true;
}

void net_telemetry_stop() {
    if (!listening) return;
    udp.stop();
    listening = false;
    // Keep the last client on record: a Wi-Fi blip should not force the host
    // to re-announce itself before button replies can flow again.
    Serial.println("[NET] Telemetry listener down");
}

bool net_telemetry_is_listening() {
    return listening;
}

// Splits a datagram into newline-framed JSON objects and hands each to the
// router. A host that batches stats+app into one send is therefore handled
// identically to one that sends them separately.
static void dispatch_payload(char* payload, size_t len) {
    if (!packet_cb) return;

    size_t start = 0;
    for (size_t i = 0; i <= len; i++) {
        bool terminator = (i == len) || payload[i] == '\n' || payload[i] == '\r';
        if (!terminator) continue;

        payload[i] = '\0';
        char* line = payload + start;
        size_t line_len = i - start;
        // Trim leading whitespace so a pretty-printed sender still parses.
        while (line_len > 0 && (*line == ' ' || *line == '\t')) {
            line++;
            line_len--;
        }
        if (line_len > 0) {
            packet_cb(line, line_len);
        }
        start = i + 1;
    }
}

void net_telemetry_loop() {
    if (!listening) return;

    int size = udp.parsePacket();
    while (size > 0) {
        int to_read = size;
        if (to_read > NET_TELEMETRY_MAX_PACKET) {
            to_read = NET_TELEMETRY_MAX_PACKET;
            drop_count++;
            Serial.printf("[NET] Oversized datagram (%d B) truncated to %d\n",
                          size, NET_TELEMETRY_MAX_PACKET);
        }

        int read = udp.read(rx_buf, to_read);
        udp.flush();  // discard any tail beyond NET_TELEMETRY_MAX_PACKET
        if (read > 0) {
            rx_buf[read] = '\0';

            client_ip = udp.remoteIP();
            client_port = udp.remotePort();
            strlcpy(client_ip_str, client_ip.toString().c_str(), sizeof(client_ip_str));
            have_client = true;

            last_rx_ms = millis();
            rx_count++;

            dispatch_payload(rx_buf, (size_t)read);
        }

        size = udp.parsePacket();
    }
}

bool net_telemetry_send_line(const char* json) {
    if (!listening || !have_client || !json) return false;
    if (!udp.beginPacket(client_ip, client_port)) return false;
    udp.write((const uint8_t*)json, strlen(json));
    udp.write((const uint8_t*)"\n", 1);
    return udp.endPacket() == 1;
}

bool net_telemetry_has_client() {
    return have_client;
}

const char* net_telemetry_client_ip() {
    return have_client ? client_ip_str : "";
}

uint16_t net_telemetry_client_port() {
    return have_client ? client_port : 0;
}

unsigned long net_telemetry_last_rx_ms() {
    return last_rx_ms;
}

uint32_t net_telemetry_rx_count() {
    return rx_count;
}

uint32_t net_telemetry_drop_count() {
    return drop_count;
}
