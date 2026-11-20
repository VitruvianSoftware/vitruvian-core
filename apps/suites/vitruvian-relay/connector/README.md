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
| `vrelay status` | Sign-in, device, link state, whether the Mac is being kept awake, and which rules are in use |
| `vrelay pause` | No tools visible, every call refused, at once |
| `vrelay resume` | Undoes `pause` |
| `vrelay reload` | Re-reads `rules.toml` after you edit it (until then the old rules stay in use) |
| `vrelay logout` | Removes the sign-in and the device key; the running agent drops its link |
| `vrelay tools` | Lists desktop-commander's tools and what the rules do with each (`--raw` for its own list) |
| `vrelay run` | The agent itself (launchd runs it) |

## Files

| Where | What |
|---|---|
| `~/Library/Application Support/vrelay/` (`VRELAY_HOME`) | `device.json`, `rules.toml`, `status.json`, `seen_calls.jsonl`; folder 0700. The sign-in and the device key are in the login Keychain (service `dev.vitruvian.vrelay`, accounts `tokens` and `device_key`); a `token.json` or `device.key` left by an older vrelay is moved there the first time it runs. `VRELAY_SECRETS=file` keeps them as `token.json` and `device.key` (0600) instead |
| `~/Library/Logs/vrelay/` (`VRELAY_LOG_DIR`) | `calls.log` (every call, arguments included, 0600, 10 MiB then rotated) and `vrelay.log` (the agent's own output, cut back past 10 MiB) |
| `~/.local/share/vrelay/` | The installed binary, desktop-commander and `bridge.json` |
| `~/Library/LaunchAgents/com.vitruvian.vrelay.plist` | The LaunchAgent |

A remote call that names a path in these folders, or in
`~/.claude-server-commander` (desktop-commander's own log), is refused,
however the path is written (`~`, `..`, a symlink), and a search rooted at or
above them asks first. That is not a wall: a search or a terminal command you
approve can still read them (spec §7, §11 item 17).

## Rules

`rules.toml` decides what the relay sees: `hidden` tools are never
shown or callable, tools in `no_prompt` (reads, by default) run without
asking, and everything else shows an Allow / Deny dialog first. `paused =
true` turns everything off; use `vrelay pause` / `resume`, which also
reload. Nothing from the relay can change the rules.

Two more settings, both on by default. `keep_awake = true` runs
`caffeinate` while `vrelay run` is up, so a call does not find the Mac
asleep (the screen may still sleep); `vrelay status` says whether it is.
`allowed_folders = ["~"]` limits the file tools (read, write, move, search)
to those folders and what is inside them, however the path is written (`~`,
`..`, a symlink); a call outside them is refused. Terminal commands are not
path-checked.

`bazel test //apps/suites/vitruvian-relay/connector:unit_tests`
