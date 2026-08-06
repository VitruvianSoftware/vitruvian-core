# Decision record: mcp-slack remote exposure (Gemini Spark PoC)

**Status:** 5 of 6 decisions final; 1 open pending a product-intent answer from James.
**Context:** James asked whether mcp-slack — today a local stdio tool for harnesses like Claude Code —
could also serve remote agent harnesses (Google Gemini Spark). Wren and Atlas scoped the six calls
below by reading `mcp-slack/src/index.ts` and `mcp-slack/manifest.json` directly; James answered on
2026-08-06. This doc is the product-level companion to
[`application-alignment-gaps.md` §3.5](application-alignment-gaps.md#35-no-written-app-type--hosting-target-rule),
which Atlas annotates on the hosting side — this doc is not a duplicate of that annotation.

## The generalizable pattern

**When a local stdio tool goes network-exposed, the credential is the access-control boundary —
not the transport, and not a tool-list filter you maintain by hand.**

mcp-slack holds two Slack tokens and picks one per API call. They partition cleanly:
- **Bot token** (`manifest.json` bot scopes): every method is a read. Zero write scopes granted.
- **User token** (`manifest.json` user scopes): every write, plus search — and every write posts
  **as the human**, not as the bot.

That partition is enforced by Slack server-side (a bot token literally cannot call a write method
it wasn't granted), which is a stronger property than a tool-list filter the server maintains and
can drift as tools are added. The question to ask on every future remote-exposure request is:
**"Which credential does the remote path get, and is the scoping control actually enforcing —
or does it just look like it is?"**

The second half of that question matters because it isn't always obvious. Two traps this PoC found
by reading the source rather than assuming:
- `SLACK_CHANNEL_IDS` reads like an allowlist. It isn't — it only filters `listChannels`'s output;
  `getChannelHistory`, `getChannelInfo`, and `getThreadReplies` take a caller-supplied channel ID
  with no validation against it at all. A caller who already knows an ID reads that conversation
  regardless of the env var. The fix is to enforce the allowlist at every read call, not just the
  listing one — and to make it a required config value with no default, so the boundary can't be
  silently unset.
- The bot/user scope split is not a fixed constraint of the Slack app — it's a manifest file this
  repo owns. "Bot-only" and "the write surface" are not opposite ends of a fixed spectrum; scopes
  can be moved from the user token to the bot token by editing `manifest.json` and re-installing
  the app. That reframes "read-only vs full toolset" from a binary into a design choice about
  **whose identity writes post under**, which is the actual product question (see Decision 6 below).

## The six decisions

| # | Decision | Answer | Rationale |
|---|---|---|---|
| 1 | Tenancy | **Single-tenant.** One deployment, one set of Slack tokens; every connected agent acts as James's Slack identity. | `src/index.ts:802-808` reads tokens once at process start — one identity per process. Multi-tenant needs per-request token resolution and a token store: a rewrite of the server's core, not a transport addition. Biggest scope lever in the list. |
| 2 | Who may connect | **James's Zitadel user only**, for the PoC. | Under single-tenant, OAuth is the only thing between a caller and the workspace, so "which Zitadel subjects get a token" is the access-control decision. |
| 4 | Public exposure via cloudflared, gated only by Zitadel | **Accepted.** | Spark is Google-hosted and must reach the endpoint over the public internet through the existing tunnel. Cloudflare Access can't gate it (Spark authenticates via OAuth 2.1, not Access), so Zitadel is the only gate — reasonable for a scoped PoC with decisions 1–3 in place. |
| 6a | Verification | James verifies end-to-end using his `james.nguyen@gmail.com` Gemini account (has Spark access). | Confirms who runs the acceptance test; not a scope decision. |
| 6b | Target Slack workspace | **The "abrial" workspace** — the same one James's local mcp-slack (stdio) already connects to. | Needs a config-level confirmation (team ID, existing bot install) that the remote path targets the same workspace as the working local path, not a new install. |

## Open — needs a product-intent answer from James

**Decision 3/7 collapsed as "bot-only" during scoping, but James's decision 6 reopens it.**

Wren and Atlas's recommendation was bot-only credential on the HTTP path: the user token never
enters the cluster, every write is dropped from the remote tool list, and the read surface is
enforced by Slack's own scope check rather than code the team has to keep correct. James's answer 6
asks for **read + write across multiple channels**, specifically to let Spark post scheduled
reports/updates — which the bot token as currently scoped (`manifest.json:16-27`, zero write
scopes) cannot do.

Re-adding the user token to satisfy this reopens the exact risk Wren and Atlas flagged: a
publicly-reachable endpoint, gated only by Zitadel, that can post to Slack **as James personally**
and search everything his personal account can see (DMs and private channels included) — not just
the channels intended for reports.

**There is a third option the team hasn't put in front of James yet, surfaced while writing this
record:** since the bot/user scope split is a manifest the repo owns (see pattern above), write
scopes needed for reports/updates (`chat:write` at minimum; `channels:write:topic` if topic-setting
matters) can be added to the **bot's** scope list instead of relying on the user token. That
preserves the credential-enforced boundary — Slack still checks scopes server-side, membership in
a channel is still required, `SLACK_CHANNEL_IDS` still bounds which channels are reachable — while
giving Spark the write capability decision 6 asks for.

The tradeoff: posts would go out under the bot's identity ("Vitruvian Slack MCP"), not under
James's own name. That's a real product question, not an implementation detail:

> **For scheduled reports/updates via Spark, should posts appear as James, or as a bot?**

- **Bot identity** (recommended): expand bot scopes in `manifest.json` to include `chat:write`
  (+ `channels:write:topic` if needed), keep the user token out of the cluster entirely, scope
  writes to the same `SLACK_CHANNEL_IDS` allowlist already planned for reads. Requires a Slack app
  re-install in the abrial workspace to grant the new bot scope (workspace-admin action) and a
  small code change on Wren's transport PR to route writes through the bot token on the HTTP path.
- **James's identity**: re-admit the user token to the HTTP path as Atlas/Wren scoped it before this
  answer — wider blast radius, explicitly accepted, not defaulted into.

This is the one call still blocking a final "all defaults" read of decision 6. Everything else in
this table is unaffected by the answer.

## Deferred, not closed

This PoC answers "can Spark talk to Slack at all," not "what's the long-term shape." Explicitly
deferred rather than decided:

- **Multi-tenancy** — decision 1 picked single-tenant for scope reasons, not because multi-tenant
  was rejected as a future need.
- **Who beyond James may connect** — decision 2 is a PoC-scoped answer (one Zitadel subject); no
  process exists yet for widening it.
- **Whether search returns to the remote path** — dropped in every option on the table above
  (`searchMessages`, `searchFiles`, `lookupCanvasSections` are user-token-only and none of this
  record's paths restore them). Revisit if a use case needs it.
- **Homelab k3s deployment lifetime** — James's answer to the team's throwaway-vs-permanent question
  was "potentially permanent, revisit after brainstorming monetization," which is a live change from
  the team's throwaway-then-Cloud-Run-migrate recommendation. That has infra consequences (backup/DR,
  on-call expectations, and Atlas's §3.5 annotation, which was written assuming throwaway) that are
  Atlas/Pace's to work through, not re-litigated here — flagged so it isn't lost.

## What would reverse each decision

- **Single-tenant (1):** a second person needing their own Slack identity through Spark.
- **Zitadel-only, James (2):** another person or service needing to connect.
- **Public exposure via cloudflared (4):** if Zitadel is ever compromised or found insufficient as
  the sole gate, or if Spark starts supporting an auth model Cloudflare Access can gate.
- **Bot-only vs. bot+write scopes vs. user token (open):** whichever way James answers the identity
  question above; revisit if the write surface needs to grow beyond `chat:write` (canvases,
  bookmarks, pins-write) since those stay user-token-only either way.
- **Homelab permanence:** the monetization brainstorm James mentioned; also revisit if this cluster
  needs uptime/on-call guarantees it doesn't have today as a laptop-hosted PoC target.
