<!--
Copyright (c) 2026 VitruvianSoftware

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

# Vitruvian Relay protocol

The JSON frames the relay and `vrelay` send each other over the
`/connect` WebSocket (`src/lib.rs`), and the numbers both ends must agree
on, so neither can drift:

| Constant | Value | Meaning |
|---|---|---|
| `PROTOCOL` | 2 | Protocol version spoken on `/connect` |
| `MAX_FRAME_BYTES` | 4 MiB | Largest frame; bigger tool output is cut with a note |
| `PING_SECS` | 20 | Ping interval when idle |
| `IN_CALL_PING_SECS` | 2 | Ping interval while a call is in flight |
| `MAX_MISSED_PINGS` | 3 | Missed pings (or silent intervals) that mean the link is gone |
| `CALL_BUDGET_SECS` | 90 | Longest a call may take, dialog included (under the tunnel's ~100 s limit) |
| `ACK_SECS` | 5 | How long the relay waits for `ack` after sending `call` |
| `APPROVAL_REPLY_SECS` | 10 | How long the relay waits on `pending` before returning `check_request` |
| `RECONNECT_GRACE_SECS` | 10 | How long calls and dialogs survive a dropped link |

Frames: `hello`, `welcome` / `reject`, `call`, `ack`, `start`, `pending`,
`result`, `result_ack`, `cancel`, `tools_changed`, `ping` / `pong`. The `hello`
is signed with the device key over the token's hash (`hello_message`).

`bazel test //apps/suites/vitruvian-relay/protocol:unit_tests`
