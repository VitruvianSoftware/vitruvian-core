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

# vrelay, the Mac connector

`vrelay` runs as a LaunchAgent on your Mac. It signs in once, keeps a link
to the relay, and runs the calls that come over it through a pinned
desktop-commander (`dc/`), within the rules in `rules.toml`.

## Install and remove

```
bazel run //apps/suites/vitruvian-relay/connector/scripts:install    # -- --unsigned, -- --node <path>
bazel run //apps/suites/vitruvian-relay/connector/scripts:uninstall
```

The installer signs the binary with your Developer ID, copies
desktop-commander next to it, checks that search works, and only then
replaces a running agent. Uninstall keeps your sign-in, device key, rules
and logs.

## Commands

| Command | What it does |
|---|---|
| `vrelay login` | Signs in (device flow) and registers this Mac; prints the URL to add in Claude |
| `vrelay status` | Sign-in, device, link state, and which rules are in use |
| `vrelay pause` | No tools visible, every call refused, at once |
| `vrelay resume` | Undoes `pause` |
| `vrelay reload` | Re-reads `rules.toml` after you edit it (until then the old rules stay in use) |
| `vrelay logout` | Removes the sign-in; the running agent drops its link |
| `vrelay tools` | Lists desktop-commander's tools and what the rules do with each (`--raw` for its own list) |
| `vrelay run` | The agent itself (launchd runs it) |

## Files

| Where | What |
|---|---|
| `~/Library/Application Support/vrelay/` (`VRELAY_HOME`) | `token.json`, `device.json`, `device.key`, `rules.toml`, `status.json`, `seen_calls.jsonl`; folder 0700 |
| `~/Library/Logs/vrelay/` (`VRELAY_LOG_DIR`) | `calls.log` (every call, arguments included, 0600, 10 MiB then rotated) and `vrelay.log` (the agent's own output, cut back past 10 MiB) |
| `~/.local/share/vrelay/` | The installed binary, desktop-commander and `bridge.json` |
| `~/Library/LaunchAgents/com.vitruvian.vrelay.plist` | The LaunchAgent |

Remote calls can never read or write these folders, nor
`~/.claude-server-commander` (desktop-commander's own log); a search that
would reach them asks first.

## Rules

`rules.toml` decides what the relay sees: `hidden` tools are never
shown or callable, tools in `no_prompt` (reads, by default) run without
asking, and everything else shows an Allow / Deny dialog first. `paused =
true` turns everything off; use `vrelay pause` / `resume`, which also
reload. Nothing from the relay can change the rules.

`bazel test //apps/suites/vitruvian-relay/connector:unit_tests`
