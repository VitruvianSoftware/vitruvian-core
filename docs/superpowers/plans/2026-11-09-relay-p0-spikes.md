---
status: in progress
date: 2026-11-09
---

# Relay P0: the four spikes

Spec: [2026-11-07-vitruvian-relay-design.md](../specs/2026-11-07-vitruvian-relay-design.md) §10.
Each spike ends in a written yes or no with evidence. This file is the record.

| Spike | Question | Status |
|---|---|---|
| A | Can ChatGPT and Claude add an OAuth-protected MCP on our domain, with Zitadel sign-in? | **Claude: yes, live** (2026-11-11, claude.ai). ChatGPT: yes on paper for one user, needs open registration for many; not tried live |
| B | Does Zitadel's device flow work from a command-line app? | **Yes** (2026-11-11), with `relay-spike-client login` |
| C | Does a WebSocket through the Cloudflare Tunnel stay up for 24 hours? | **No for one connection, yes for the service** (2026-11-12). 10 drops in 24 hours, connected 99.3% of the time; reconnecting is mandatory |
| D | Can a connector drive unmodified `desktop-commander` over stdio? | **Yes** (2026-11-12), version 0.3.1 run through Bazel. The connector must kill the whole process group, turn telemetry off and redirect its feature-flag fetch |

## Live results (2026-11-11)

### A (Claude): yes

- Added in claude.ai as a custom connector: URL `https://relay-spike.ipv1337.dev/mcp`,
  client id `398912442404439866`. Claude read the server's metadata and picked
  "Sign in now" and "Use your own OAuth client" by itself.
- Sign-in went through Zitadel and back to Claude. Both tools ran from a chat:
  `whoami` returned `subject 378818267051722263 via client 398912442404439866`,
  `echo` returned its input.
- The server log shows every request (initialize, tools/list, tools/call)
  carrying that subject and client id, so each call was a verified token.
- Claude also sends `server/discover`, which the spike doesn't implement. Claude
  carried on without it; the relay should answer it.
- Not yet tried: the Claude phone app.

### B: yes

- `bazel run //apps/suites/relay/spike:relay-spike-client -- login` asked
  Zitadel for a device code with the relay project's audience scope, James
  approved it in the browser, and a token came back 97 seconds later, with a
  refresh token.
- The access token is a JWT: `sub` 378818267051722263, `client_id`
  398912442404505402 (the connector), and the relay project
  398912441632687930 in `aud`. **`azp` is absent**; Zitadel puts the issuing
  client in `client_id`. The verifier pins `client_id`, so this passes.
- `aud` also lists the Claude client id (398912442404439866), though the
  connector asked for nothing of Claude's. This repeats the earlier finding:
  audience is not proof of which app a token is for. Pin the client id.
- The access token lives 12 hours.
- One snag: the device-approval page uses Zitadel's older login screen, which
  doesn't share the session of the newer one Claude's sign-in used, so James
  signed in twice. Worth fixing before real users see it.

### C: no for one connection, yes with reconnects

`relay-spike-client hold --hours 24` (now `bazel run //apps/suites/vitruvian-relay/spike:vitruvian-relay-spike-client -- hold`) ran
from 2026-11-11 18:15 to 2026-11-12 18:15 PST from James's MacBook, over home
Wi-Fi, to `wss://relay-spike.ipv1337.dev/connect`. It sent a probe every 30 s
and reconnected with backoff.

| | |
|---|---|
| Time connected | 85,836 of 86,400 s (**99.3%**) |
| Connections | 11 (**10 drops**) |
| Longest single connection | 45,836 s (12.7 h) |
| Probe round trip | p50 62 ms, p95 152 ms, max 462 ms (2,814 probes) |
| Longest gap | 352 s |

The 10 drops had three causes:

- **8 resets from the network**, between 06:59 and 15:06, after 5 minutes to
  12.7 hours. They were TCP resets or closes without a WebSocket close frame.
  Each time, the client was back in about 1 s. Which hop reset them (home
  network, Cloudflare's edge, or `cloudflared`) is **not established**: nothing
  on the server side was logged for these.
- **2 server outages, 17:36 and 17:59.** The client heard nothing for 90 s,
  then Cloudflare answered 503 or 504 for up to 6 minutes. The relay-spike pod
  was running on the node `james-mbp16`, a laptop, which went `NotReady` twice
  in that window. The pod was then evicted and rescheduled on `nuc9i9` (cluster
  events, 18:04). These are the gaps of 3 to 6 minutes.
- **1 token refresh failed** on a reset (06:59, same moment as a drop) and
  succeeded on the next try a second later.

What this means for the relay:

- **The connector must reconnect by itself, quietly and quickly.** A drop every
  few hours is normal, and the backoff used here was enough.
- Calls in flight when a connection drops are lost, so the relay has to fail
  them cleanly and Claude has to be able to retry them.
- **Production relay pods must not run on laptop nodes.** Pin them to always-on
  nodes, and run more than one replica so a node going away isn't an outage.
- The test client and the laptop node may be the same machine. Repeating the
  test from an always-on host would tell home-network resets apart from
  Cloudflare ones. That isn't needed for P0: the design has to reconnect either
  way.

## Evidence so far (2026-11-09)

### Our Zitadel, from its public discovery document

Read from `https://auth.ipv1337.dev/.well-known/openid-configuration`, a public,
read-only request:

- `device_authorization_endpoint` is present, and `grant_types_supported`
  includes `urn:ietf:params:oauth:grant-type:device_code`. **Spike B's endpoint
  exists.**
- `code_challenge_methods_supported` is `["S256"]`, which both AI apps require.
- `token_endpoint_auth_methods_supported` includes `none`, so public clients work.
- There is **no `registration_endpoint`**: dynamic client registration is off.
- There is no `client_id_metadata_document_supported`, so Client ID Metadata
  Documents aren't offered.
- There is no `authorization_response_iss_parameter_supported` (RFC 9207).
- `/.well-known/oauth-authorization-server` returns 404. Only OIDC discovery is
  served.

### Claude (official docs, claude.com)

- Custom connectors work on Free, Pro, Max, Ultra, Team and Enterprise. Free
  allows one.
- Three ways to register a client: Claude's published identity (needs CIMD on the
  server), automatic registration (needs DCR), or our own client.
- **Our own client works with our Zitadel as it is today.** Its callback for
  claude.ai, desktop and mobile is `https://claude.ai/api/mcp/auth_callback`.
- What the resource server must do: answer `401` with a `WWW-Authenticate` header
  pointing at protected-resource metadata, make `resource` match the MCP URL
  exactly, and list our issuer first. The hosted Slack MCP already does this.

### ChatGPT (official docs, developers.openai.com)

- It supports CIMD (preferred), DCR and predefined clients. PKCE with S256 is
  required.
- **The callback depends on the server.** With RFC 9207 it is the fixed
  `https://chatgpt.com/connector_platform_oauth_redirect`. Without it, which is
  our case, it is `https://chatgpt.com/connector/oauth/{callback_id}`, unique per
  connector.
- So one pre-registered client works for a single connector (spike A), but not
  for a product with many users. The product needs DCR.
- **Not confirmed:** which plans can add a custom MCP server. Third-party sources
  say Business, Enterprise and Edu. The official pages read here don't say.

### Zitadel dynamic client registration (zitadel.com docs)

- It exists and is off by default. It is turned on per instance in the security
  settings.
- For MCP clients it has to be **open**, meaning no authentication to register.
  On our shared instance that means anyone could create clients. Whether to do
  that is now spec §11 question 7.
- The docs don't say which version first shipped it, so whether our running
  Zitadel has it is unknown. Enabling it would show.

### Desktop Commander, read from its source (spike D)

These came from reading code at `d05721a`, not from running it:

- Its config lives at a fixed path, `~/.claude-server-commander/config.json`, with
  no override. A connector therefore shares settings with any Desktop Commander
  the user already runs for Claude Desktop. Changing `HOME` for the child would
  also change `~` for every command the user runs through it, so that's not a fix.
- **Telemetry is on by default.** The connector has to ask at setup and set it.
- It logs every tool call, with arguments, to `claude_tool_call.log` in that
  folder.
- It needs Node 22.12 or newer. The latest published version is 0.3.1
  (`sha512-cx7KTscLF951adHmDLVCDIVTqJ/Bg1LtdRILZoo5wa/UMeyOfMAuOJOEBulNMKBKb5Xd3nHDQnB9aXroN9Fw5A==`).

### D: yes (live run, 2026-11-12)

Unmodified `@wonderwhy-er/desktop-commander` 0.3.1, pinned by checksum (the one
above) and built by rules_js on macOS with Node 22.21.1. A Python driver ran it
over stdio with `HOME` set to a throwaway folder. It ran four times. Start-up,
stdout, polling and shutdown came out the same each time. The crash result is
from the last run, after the driver was fixed to kill Node itself rather than
Bazel's launcher.

- **Start-up:** the first `initialize` answer came 340–550 ms after spawn
  (cold), 250–360 ms on a restart. It reports protocol `2025-06-18`, has 25
  tools, and declares the capabilities `logging`, `prompts`, `resources` and
  `tools`.
- **stdout is clean.** Every line was a JSON-RPC 2.0 message: no stray output
  in four runs, and nothing on stderr. Its own logs go out as
  `notifications/message` (about a dozen at start-up, more during calls). The
  connector should forward or drop those, not treat them as replies.
- **Command output is polled, not pushed.** `start_process` waits up to
  `timeout_ms`, then returns the output so far and a PID. After that, the client
  calls `read_process_output` each time it wants more. Each call returned only
  the new lines, about one second apart, and the last one gave the exit code. The
  relay needs no streaming of its own for this: it forwards each call.
- **Shutdown:** closing stdin makes it exit cleanly (code 0) within 40 ms.
- **Crash:** when the Node process was killed mid-call, stdout closed within
  5 ms and the pending call got no answer. **The command it had started
  (`sleep 30`) kept running.** Commands are its children, so the connector must
  start it in its own process group and kill the group, not just the PID.
- **Wrapper trap (Bazel only):** `bazel run`'s launcher is a shell script with
  Node underneath. Killing only the launcher left Node running with stdout open,
  so no EOF arrived. A connector that starts it through a wrapper must kill the
  group for the same reason.
- **Telemetry:** `DESKTOP_COMMANDER_DISABLE_TELEMETRY=1` stops every event
  before one is built (`utils/capture.js`). The connector should set it, not
  rely on the shared config file.
- **It phones home for feature flags even with telemetry off.** At start-up and
  every 30 minutes it fetches `https://desktopcommander.app/flags/v2/production.json`
  and caches it in `feature-flags.json`. The only way to change this is to
  redirect it with `DC_FLAG_URL`. The connector should point that at a local
  file or an address that refuses the connection.
- **Its install script reports the install** (`postinstall` runs
  `track-installation.js`, which uses HTTPS). rules_js ran no install scripts:
  the build had only extract and symlink actions.
- **Files it wrote** under `~/.claude-server-commander/`: `config.json`,
  `feature-flags.json`, `tool-history.jsonl` and `claude_tool_call.log`. The log
  records every call with its full arguments. `HOME` controls where these go.

Not committed: pinning it changed how some unrelated Backstage webpack packages
resolve in `pnpm-lock.yaml`. That's too much reach for a spike, so the run was
made from a local branch. To repeat it:
1. Add a workspace package with `"@wonderwhy-er/desktop-commander": "0.3.1"`.
2. Run `bazel run //tools/pnpm:lock`.
3. Add a BUILD file with `npm_link_all_packages` and the package's
   `desktop_commander_binary`.

### One correction to the spec, recorded there too

The sibling `zitadel-apps-mcp-slack` stack found that in this Zitadel, a token's
`aud` is caller-authored. The relay must authorise on client id (`azp`) and
subject.

## Steps

- [x] Research sign-in support for Zitadel, Claude and ChatGPT
- [x] `infrastructure/pulumi/platform/zitadel-apps-relay`: project, connector
      (device flow) and Claude clients, role check limited to James, apply workflow
- [ ] James dispatches `zitadel-apps-relay-apply.yaml` (`preview`, then `up`) and
      notes the client ids. Agents can't dispatch it (README explains why)
- [x] **B:** run the device flow from a terminal against `relay-connector`, James
      approves in the browser, and the access token decodes as a JWT with the
      expected `azp` and `sub`
- [ ] Spike server on the homelab (one small service, chart, image build, GitOps
      app): `/mcp` behind OAuth with one echo tool, protected-resource metadata,
      and `/connect` as a WebSocket with ping/pong
- [x] **A (Claude, web; phone app still to try):** James adds `https://<spike-host>/mcp` in Claude with the
      `relay-claude` client id, signs in, and the echo tool runs from claude.ai
      and from the Claude phone app
- [ ] **A (ChatGPT):** James starts adding the connector in ChatGPT and copies its
      callback into `chatgptRedirectUris`, then re-apply, then finish. Only if his
      plan allows custom MCP servers
- [x] **C:** a WebSocket client on this Mac holds `/connect` open for 24 hours,
      logging drops, reconnect times and ping round trips
- [x] **D:** add a Bazel route for running an npm package (`//tools/pnpm:lock`,
      #4663), then run it
- [ ] Write the yes or no for each spike here and update spec §10 and §11
