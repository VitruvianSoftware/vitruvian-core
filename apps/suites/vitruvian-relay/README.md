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

# Vitruvian Relay

Lets an AI app (Claude first) run tools on your own Mac from anywhere. The AI
app talks MCP to a relay server on the homelab; a small agent on the Mac,
`vrelay`, keeps a WebSocket open to the relay and runs each call through
[desktop-commander](https://github.com/wonderwhy-er/DesktopCommanderMCP),
asking you first for anything that is not a read. Design:
[the spec](../../../docs/superpowers/specs/2026-11-07-vitruvian-relay-design.md).

```
AI app ──MCP/HTTPS──▶ relay (homelab) ◀──WebSocket── vrelay (your Mac) ──stdio──▶ desktop-commander
```

## What is here

- [relay](./relay/README.md): the server: MCP for AI apps, device
  registration, the `/connect` WebSocket.
- [protocol](./protocol/README.md): the JSON frames both ends speak, and the
  limits they share.
- [connector](./connector/README.md): `vrelay`, the Mac agent, and its
  installer.

## Build and test

```
bazel test //apps/suites/vitruvian-relay/...
```

`relay:vitruvian_relay_e2e_test` runs the real relay against the real
connector. Each unit also has a `rust_clippy` target that CI builds.
Re-lock the Rust crates with
`bazel run //tools/crates:lock -- --dir apps/suites/vitruvian-relay`.
