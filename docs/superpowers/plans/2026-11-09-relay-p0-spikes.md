---
status: in progress
date: 2026-11-09
---

# Relay P0: the four spikes

Spec: [2026-11-07-vitruvian-relay-design.md](../specs/2026-11-07-vitruvian-relay-design.md) §10.
Each spike ends in a written yes or no with evidence. This file is the record.

| Spike | Question | Status |
|---|---|---|
| A | Can ChatGPT and Claude add an OAuth-protected MCP on our domain, with Zitadel sign-in? | Claude: yes on paper. ChatGPT: yes for one user, needs open registration for many. Live test waits on B's stack and a spike server |
| B | Does Zitadel's device flow work from a command-line app? | Endpoint confirmed live. End-to-end test waits on the stack being applied |
| C | Does a WebSocket through the Cloudflare Tunnel stay up for 24 hours? | Not started. Needs a spike server on the homelab |
| D | Can a connector drive unmodified `desktop-commander` over stdio? | **Blocked.** The repo guard refuses `npm`/`npx`, and no Bazel target exists. Answered from source code where possible |

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

### Desktop Commander, read from its source (spike D, partial)

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

What still needs a run: start-up time, whether stdout carries only JSON-RPC,
streamed process output, and behaviour on a crash. That needs the package
installed, which needs an `npm` route.

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
- [ ] **B:** run the device flow from a terminal against `relay-connector`, James
      approves in the browser, and the access token decodes as a JWT with the
      expected `azp` and `sub`
- [ ] Spike server on the homelab (one small service, chart, image build, GitOps
      app): `/mcp` behind OAuth with one echo tool, protected-resource metadata,
      and `/connect` as a WebSocket with ping/pong
- [ ] **A (Claude):** James adds `https://<spike-host>/mcp` in Claude with the
      `relay-claude` client id, signs in, and the echo tool runs from claude.ai
      and from the Claude phone app
- [ ] **A (ChatGPT):** James starts adding the connector in ChatGPT and copies its
      callback into `chatgptRedirectUris`, then re-apply, then finish. Only if his
      plan allows custom MCP servers
- [ ] **C:** a WebSocket client on this Mac holds `/connect` open for 24 hours,
      logging drops, reconnect times and ping round trips
- [ ] **D:** add a Bazel route for running an npm package (or settle another way
      to get `desktop-commander` onto the machine for the spike), then run it
- [ ] Write the yes or no for each spike here and update spec §10 and §11
