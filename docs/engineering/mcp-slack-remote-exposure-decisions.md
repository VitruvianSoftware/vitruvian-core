# Decision record: mcp-slack remote exposure (Gemini Spark PoC)

**Status:** all six decisions resolved to a team-level call or a specific pending confirmation from
James; nothing is blocked on re-litigating a decision, only on three concrete admin-side actions
(see "What's still James's to do," below). **This PR (#1416) is held open by design** — Beacon's
call, 2026-08-06 — and merges at Phase 3 close, not before. The subject is still being built; a
record that chases every in-flight change costs a rewrite and a re-review each time for a document
nobody is reading yet. It gets one more correction pass if Phase 1/2 land materially different
from what's written here, then lands once, accurate, when the decisions have actually stopped
moving.
**Context:** James asked whether mcp-slack — today a local stdio tool for harnesses like Claude Code
— could also serve remote agent harnesses (Google Gemini Spark). Wren and Atlas scoped six calls by
reading `mcp-slack/src/index.ts` and `mcp-slack/manifest.json` directly; James answered on
2026-08-06; Beacon, Pace, Wren and Atlas then resolved the two answers that collided with the
team's earlier recommendations. This doc is the product-level companion to
[`application-alignment-gaps.md` §3.5](application-alignment-gaps.md#35-no-written-app-type--hosting-target-rule),
which Atlas annotates on the hosting side — this doc is not a duplicate of that annotation.

## The generalizable patterns

### 1. When a local stdio tool goes network-exposed, the credential is the access-control boundary

Not the transport, and not a tool-list filter maintained by hand. mcp-slack holds two Slack tokens
and picks one per API call. They partition cleanly:
- **Bot token** (`manifest.json` bot scopes): every method is a read. Zero write scopes granted
  originally.
- **User token** (`manifest.json` user scopes): every write, plus search — and every write posts
  **as the human**, not as the bot.

That partition is enforced by Slack server-side (a bot token literally cannot call a write method
it wasn't granted), which is a stronger property than a tool-list filter the team maintains and can
drift as tools are added. The question to ask on every future remote-exposure request: **"Which
credential does the remote path get, and is the scoping control actually enforcing — or does it
just look like it is?"**

Traps this PoC found by reading the source rather than assuming:
- `SLACK_CHANNEL_IDS` reads like an allowlist. It only filters `listChannels`'s output —
  `getChannelHistory`, `getChannelInfo`, and `getThreadReplies` take a caller-supplied channel ID
  with no validation against it. Fix: enforce the allowlist at every read *and write* call, as a
  required config value with no default.
- The bot/user scope split is not a fixed constraint of the Slack app — it's a manifest this repo
  owns. Scopes can be moved from the user token to the bot token by editing `manifest.json` and
  re-installing the app (see "Option A," below), which reframes "read-only vs. full toolset" as a
  design choice about **whose identity writes post under**, not a fixed tradeoff.
- Within a scope, take the narrowest one that satisfies the ask: `chat:write` lets the bot post only
  where it's been invited (a second Slack-enforced boundary that composes with the channel
  allowlist); `chat:write.public` would let it post to any public channel in the workspace,
  quietly undoing the containment. The team caught this before it shipped — worth checking every
  time a scope is added, not just once.

### 2. A claim about a third-party API is only settled when someone links the vendor's page and dates it

**This is the most valuable thing to preserve from this thread**, per Beacon (2026-08-06T18:56:09Z),
and it's worth recording as a standing rule rather than an anecdote. Wren's first message asserted
"Spark requires OAuth 2.1, no bearer-token fallback." That claim was repeated as settled fact across
four subsequent messages from three different agents — including Beacon citing it back as verified
evidence when closing out the Phase 0 transport question — and nobody linked the vendor doc until
Wren went and read it directly. The actual behavior differs in ways that changed real Zitadel client
config: it's OAuth 2.0 with *optional* PKCE, a pre-registered confidential client with no dynamic
registration and no `/.well-known/` discovery requirement, and a **fixed Google redirect URI**
identical across every environment — not a per-env callback the team had been carrying as a Zitadel
work item since the second message in the thread.

Nobody here was careless; the claim was close enough to be useful and wrong in exactly the details
that drive IdP configuration, and it looked verified because confident people kept restating it.
**Rule: a teammate's restatement of a claim is not a source, and neither is your own prior note.**
Before a build proceeds on a claim about a third-party API, someone links the vendor's page and
dates the check. Apply this the next time a remote-exposure (or any external-integration) thread
opens with an assumption about what the other side "requires."

### 3. An audience claim is only a boundary at the granularity the IdP scopes it to

Surfaced by Wren while reviewing this record, generalized by Beacon: mcp-slack's Zitadel OIDC
client lives in its **own** Zitadel project (PR #1417, `zitadel-apps-mcp-slack`) rather than as a
second application inside oauth-user-inspector's existing project — and the reason isn't tidiness.
Zitadel's audience-granting scope is `urn:zitadel:iam:org:project:id:{projectId}:aud`, which is
scoped to the **project**, not the individual application. Had mcp-slack's client been created
inside oauth-user-inspector's project, a token minted with that project's audience would have
validated at *both* apps — mcp-slack's local `aud` check would have kept passing while silently
providing no isolation at all between the two integrations.

The general form: **before trusting an `aud` (or any claim an IdP lets you check locally), confirm
what granularity the IdP actually issues and scopes it at.** A claim that looks like it's
per-application may really be per-project, per-org, or per-tenant — and a validation that passes is
not the same thing as a boundary that holds. Check this any time a new OIDC/OAuth client is added
to an IdP that already hosts another app's client, not just once per IdP.

### 4. Reviewing a diff is not reviewing the file, and only one of them can support a completeness claim

Per Beacon (2026-08-06T20:09:23Z), on itself: reviewing PR #1418's channel-allowlist enforcement,
Beacon grepped the *diff* for `this.guard(`, found twelve call sites, verified each was correctly
placed, and reported allow-list coverage as complete. Atlas then found two channel-scoped methods
— `addBookmark`, `createCanvas` — that name a channel in their signature but were never wired to
the guard at all, because they weren't touched by this PR and so could never have appeared in the
diff Beacon searched. Not exploitable (both are user-token-only methods, independently withheld
from the HTTP tool list), but missed for the same reason `SLACK_CHANNEL_IDS` originally covered
only `listChannels`: enforcement present everywhere someone thought to add it, silently absent
wherever they didn't need to touch the code to leave it out.

**"Every guard added here is correct" and "every path that needs a guard has one" are different
assertions, and only the file — never the diff — can support the second one.** A diff is bounded to
lines the PR touched, so a search over it can prove a change is right but can never prove nothing
was missed; an unmodified method is structurally invisible to that search regardless of how
carefully it's read. When a PR's job is closing every instance of a class of gap (an allowlist, an
auth check, an escaping rule), verify completeness against the whole file the property is supposed
to hold over, not the diff that happens to be under review. Apply this any time a review claims
"coverage is complete" for something that spans more of the codebase than the current PR touches.

## The six decisions

| # | Decision | Final answer | Rationale |
|---|---|---|---|
| 1 | Tenancy | **Single-tenant.** One deployment, one set of Slack tokens; every connected agent acts as James's Slack identity. | `src/index.ts:802-808` reads tokens once at process start — one identity per process. Multi-tenant needs per-request token resolution and a token store: a rewrite of the server's core, not a transport addition. |
| 2 | Who may connect | **Zitadel-native subject, no Google social login.** Atlas confirmed no social-login IdP is configured on the Zitadel instance (`gitops/argocd/platform/zitadel/applicationset.yaml`); adding one is new config work that would put Google in the trust chain directly in front of the Slack workspace, for no PoC benefit. James logs into `auth.ipv1337.dev` and reports which subject he lands on — if only the bootstrap admin exists, Atlas creates a dedicated non-admin user in Phase 2 rather than gating the workspace behind the instance-admin account. | Keeps the Gemini test account (client-side) and the Zitadel subject (gate-side) cleanly separate — conflating them was an early gap in the thread that Beacon caught. |
| 3 | Slack write credential (was bot-only/read-only; reopened by decision 6) | **Option A: add `chat:write` only (no `chat:write.public`) to the bot's scope, reinstall the app.** No user token enters the cluster. Writes on the HTTP path route through the bot token; stdio keeps user-token routing unchanged. | See "Option A" section below — the full resolution, including the reinstall/token-rotation consequence everyone needs to sequence around. |
| 4 | Public exposure via cloudflared, gated only by Zitadel | **Accepted.** | Spark is Google-hosted and reaches the endpoint over the public internet through the existing tunnel; Cloudflare Access can't gate an OIDC flow, so Zitadel is the only gate — reasonable given decisions 1–3. |
| 5 | Homelab k3s deployment lifetime | **Potentially permanent**, pending a post-PoC monetization decision — not throwaway-then-Cloud-Run as the team first recommended. | Changes what gets built, not just how long it lasts (see "Consequences of decision 5," below). |
| 6 | Done criteria + hostname | Spark connects → Zitadel OAuth → lists tools → **reads and writes across an explicit, allowlisted set of channels**. Deployed at **`mcp-slack.ipv1337.dev`** (not `-poc`) — "PoC" lives in the namespace and this written decision, not the URL, since renaming later turned out to be free (DNS/HTTPRoute + Spark UI edit) once Wren corrected the redirect-URI assumption, but the team is keeping the real hostname anyway now that decision 5 says permanence is the plan. | Read+write was James's actual ask (scheduled reports/updates); satisfied via Option A rather than the user token. |

## Option A — how decision 3/7's collision with decision 6 was actually resolved

Bot-only (the team's original recommendation) is read-only by Slack's own scope enforcement — the
bot's ten original scopes are all `:read`/`:history`; every write lived on the user token
(`manifest.json:28-44`), which also posts **as James personally** and can search his DMs and
private channels. James's decision 6 (read+write, multiple channels, for scheduled reports) cannot
be satisfied by bot-only as originally scoped. Three options were on the table; the team settled on
the one that preserves the credential-boundary property rather than re-admitting the user token:

| Option | Delivers #6 | Cost |
|---|---|---|
| **A. Add `chat:write` to the bot's scopes, reinstall the app — chosen** | Yes | Manifest change + Slack app reinstall (needs abrial workspace admin); posts appear as the app ("Vitruvian Slack MCP"), not as James; keeps the user token out of the cluster entirely |
| B. Ship the user token, cap the remote tool list | Yes | James's personal token on a public endpoint; posts as James; the capped-tool-list boundary is a hand-maintained filter that has to hold indefinitely now that the deployment may be permanent |
| C. Read-only PoC, defer write | No | Doesn't meet the scheduled-reports goal that motivated decision 6 |

**What Option A actually requires, in order** (this sequencing matters and was worked out across
several messages — do not shortcut it):

1. Add `chat:write` only to the bot's scopes in `manifest.json` (not `chat:write.public` — that
   would let the bot post to any public channel in the workspace, undoing the channel-allowlist
   containment). `chat.update` rides along on the same scope, so the bot can edit its own posts.
2. Reinstall the Slack app in the abrial workspace (needs admin). This **issues a new `xoxb-` bot
   token and immediately invalidates the old one** — `manifest.json:50` has
   `token_rotation_enabled: false`, so there is no graceful rotation path.
3. Update James's **local stdio mcp-slack config first**, confirm Claude Code still works against
   the new token, **then** hand it to Atlas to re-seal the cluster's sealed-secret. This ordering is
   deliberate so the two updates don't collide or leave either path broken mid-swap.
4. Invite the bot to every channel it needs to read and write — `chat:write` (and history/info/
   thread-reads) only work in channels the bot is a member of, which is a second Slack-enforced
   boundary stacked on top of the `SLACK_CHANNEL_IDS` allowlist.
5. On the code side (Wren's transport PR): `postMessage`/`replyToThread`/`updateMessage` route to
   the bot token **only on the HTTP path**; stdio keeps user-token routing exactly as today. A
   method-level (not transport-scoped) flip would silently rename James's local Claude Code posts
   from "James Nguyen" to "Vitruvian Slack MCP" — a regression nobody would notice until it
   embarrassed someone.

Bot-attribution (posts appearing as "Vitruvian Slack MCP" rather than as James) is the one piece of
Option A that is a product call, not an engineering one — flagged to James as still his to confirm
below.

## Consequences of decision 5 (potentially permanent, not throwaway)

- **The §3.5 annotation inverts.** Under "throwaway," it closes the gap as a temporary exception
  that migrates to Cloud Run. Under "permanent-pending-monetization," dev-local k3s becomes a real
  hosting target for a first-party app — which doesn't close §3.5, it makes writing the missing
  app-type → hosting-target rule *necessary*. Atlas is annotating it as a standing decision with the
  conditions that would move it (monetization → multi-tenancy → an SLA a laptop cluster can't hold),
  not as an exception with an expiry date.
- **The chart stops being a bare PoC manifest** — real resource limits, probes, and inclusion in the
  existing backup/monitoring path, since this is most of what separates "throwaway" from "something
  that stays up."
- **Multi-tenancy's deferral (see below) gets less safe to leave unexamined.** It was deferred under
  a throwaway-PoC assumption that decision 5 has since weakened.

## Zitadel/OAuth — corrected understanding (supersedes early thread claims)

Verified against Google's own docs
([custom MCP server setup](https://docs.cloud.google.com/gemini/enterprise/docs/connectors/custom-mcp-server/set-up-custom-mcp-server),
[connector setup support page](https://support.google.com/g/answer/17106276?hl=en)), by Wren,
2026-08-06:

- Transport: **Streamable HTTP only** — SSE is explicitly unsupported. This part of the original
  claim was right.
- Auth: **OAuth 2.0 with optional PKCE**, not "OAuth 2.1, no bearer-token fallback" as first stated.
  It's a pre-registered confidential client — Client ID, Client Secret, Authorization URL, and Token
  URL are pasted into Spark's UI directly; Spark appends `client_id`/`redirect_uri`/`scope` itself,
  so the Authorization URL is entered with no query parameters.
- **No dynamic client registration and no `/.well-known/` discovery requirement** — mcp-slack only
  needs to validate the bearer token Zitadel issued. This is a real scope reduction in Wren's
  transport PR (no OAuth-metadata-discovery endpoints to build).
- **The redirect URI is Google's own fixed value**, identical across every environment:
  `https://vertexaisearch.cloud.google.com/oauth-redirect`. mcp-slack is a resource server with no
  callback URL of its own — there is no per-env redirect URI to register, retiring a work item the
  thread had been carrying since the second message.
- **PKCE: not applicable, closed.** The pulumiverse/zitadel provider exposes no PKCE field on
  `ApplicationOidc`, and PKCE in Zitadel isn't an independent toggle — it's an auth *method*
  equivalent to `authMethodType = NONE`, i.e. a public client with no secret. Spark requires a
  Client ID **and** Secret (a confidential client), so that shape isn't available here regardless.
  What remains true and is worth keeping: the Zitadel instance advertises `S256` in its discovery
  document, so if Spark ever sends a `code_challenge` it's honored — that's client-side behavior
  the team neither configures nor obstructs, not something to enable server-side. (Corrected during
  PR #1416 review — an earlier draft of this doc repeated the "enable it anyway" instruction, which
  sent a reader hunting for a toggle that doesn't exist.)
- Scopes are space-separated and must include **`offline_access`** for Spark to refresh tokens
  without James re-authenticating by hand — directly relevant to his scheduled-reports use case.
- **Operational note for Phase 3 validation:** allow 5+ minutes after saving redirect-URI settings
  before testing login, or the first failed attempt reads as a bug that isn't one.

**Zitadel client registration is real, separately-scoped work, not a sub-bullet of "wire the
chart" — and it's its own project, not an app inside oauth-user-inspector's.** The OIDC client
comes from a **new sibling Pulumi stack**, `infrastructure/pulumi/platform/zitadel-apps-mcp-slack`
(PR #1417, pulumiverse/zitadel provider) — deliberately *not* a generalization of the existing
`platform/zitadel-apps` stack, which is oauth-user-inspector's: hardcoded
`OAUTH_USER_INSPECTOR_` secret prefix, GCP Secret Manager cred-sync, per-env Cloud Run redirect
origins, none of which apply to a single k3s deployment. Refactoring a live path whose client has
already been destroyed once by a bad apply, for no shared benefit, wasn't a trade worth taking.

It gets its **own Zitadel project** rather than a second application inside
oauth-user-inspector's, for the reason pattern 3 (above) exists to generalize: Zitadel's
audience-granting scope (`urn:zitadel:iam:org:project:id:{projectId}:aud`) is project-scoped, so
sharing a project would have made a token minted for either app valid at both — `aud` would stop
being a real boundary while still passing mcp-slack's local check.

Two more decisions baked into that stack, worth recording because they explain constraints
elsewhere in this doc and in Wren's PR:
- **Token validation is local JWT/JWKS verification, not introspection** (`AccessTokenType: JWT`
  on the client). Introspection would require mcp-slack to hold its own Zitadel credential
  in-cluster on top of the Slack bot token — a second secret, right after Option A's whole point
  was getting the cluster down to bot-token-plus-team-ID. JWKS is public and needs none.
- **`AccessTokenType` sits in the client's `IgnoreChanges` list**, along with `appType`, `version`,
  the three assertion booleans, and `clockSkew` — so it is the one setting Pulumi will never
  reconcile after creation. If the live client ever drifts off `JWT`, the stack reports clean
  forever while mcp-slack rejects every request, indistinguishable from a broken transport. Verify
  it once after first apply (`pulumi stack output accessTokenType`, after a `:refresh` — the
  refresh matters, since it's the only way the output reflects live state rather than what Pulumi
  last wrote) — there's no ongoing check after that.

Three hard constraints Atlas verified from the stack's own config and history apply to this and
any future Zitadel-client Pulumi stack in this repo:
- **Never hand-create the client in the Zitadel console and later adopt it into Pulumi** — the
  provider's replace-triggering fields aren't populated on import, so an import plans a
  *replacement*, which against a live app means "create replacement + delete original." That's
  what destroyed oauth-user-inspector's client on 2026-06-26 (`Errors.App.NotFound`).
- Whatever redirect URI is configured must match exactly, trailing slash included, or Zitadel
  rejects the authorize request outright (moot for Spark specifically, since its redirect URI is
  Google's fixed value, but the constraint is general to the provider).
- CI can't reach Zitadel's management API over the public edge (Cloudflare blocks non-browser
  clients); applies route over tailnet to an internal Envoy LB, which needs a one-time tailnet ACL
  prerequisite already in place.

## What's still James's to do (as of 2026-08-06T18:56Z)

Everything else in this record is a team-level call. Three items remain, and only James can resolve
them:

1. **Bot-attribution yes/no** — OK for Spark's writes to post as "Vitruvian Slack MCP" rather than
   as James personally? (Team recommendation: yes — a bot posting scheduled reports reading as a
   bot is the better outcome, but it's James's workspace identity to spend.)
2. **One Slack admin session** in the abrial workspace, all in one pass: add `chat:write` only to
   the bot's scopes and reinstall the app; update the local stdio config with the new bot token
   first and confirm Claude Code still works before handing the token to Atlas to re-seal the
   cluster secret; invite the bot to the target channels; while there, capture the **team ID**, the
   **channel IDs** for that set, and the bot's **existing private-channel/DM membership** (needed
   as the pre-flight inventory — `im:read`/`mpim:read` aren't on the bot's scopes, so this can't be
   scripted).
3. **One 30-second check** — log into `https://auth.ipv1337.dev` and report which subject is landed
   on. If it's only the bootstrap admin, say so; Atlas creates a dedicated non-admin user in Phase 2
   rather than gating the Slack workspace behind the instance-admin account.

## Deferred, not closed

This PoC answers "can Spark talk to Slack at all," not "what's the long-term shape." Explicitly
deferred rather than decided — and, per decision 5, deferred under an assumption that may not hold
much longer:

- **Multi-tenancy** — decision 1 picked single-tenant for scope reasons, not because multi-tenant
  was rejected as a future need. Decision 5's monetization direction makes this a live near-term
  question rather than a closed one; nobody should hard-code single-tenant assumptions deeper into
  the codebase than the PoC strictly needs.
- **Who beyond James may connect** — decision 2 is a PoC-scoped answer (one Zitadel subject); no
  process exists yet for widening it.
- **Whether search, canvases, bookmarks, or topic-set ever return to the remote path** — all
  remain user-token-only under Option A and stay off the HTTP path. Revisit if a use case needs
  them.
- **Homelab k3s deployment lifetime** — "potentially permanent, revisit after brainstorming
  monetization" is a live change from the team's original throwaway-then-Cloud-Run-migrate
  recommendation, with real infra consequences (see "Consequences of decision 5," above). Atlas is
  building for permanence now; the monetization call itself is unmade and is not this record's to
  make.

## What would reverse each decision

- **Single-tenant (1):** a second person needing their own Slack identity through Spark.
- **Zitadel-native, single subject (2):** another person or service needing to connect, or Zitadel
  ever needing a non-Zitadel IdP for an unrelated reason.
- **Option A / bot `chat:write` (3):** if the write surface needs to grow beyond
  `chat:write`/`chat.update` (canvases, bookmarks, pins-write, topic-set all stay user-token-only
  either way) — revisit whether Option A still holds or the user token needs to come back.
- **Public exposure via cloudflared (4):** if Zitadel is ever compromised or found insufficient as
  the sole gate, or Spark starts supporting an auth model Cloudflare Access can gate.
- **Homelab permanence (5):** the monetization brainstorm James mentioned; also revisit if this
  cluster needs uptime/on-call guarantees it doesn't have today as a laptop-hosted target.
- **Hostname `mcp-slack.ipv1337.dev` (6):** cheap to change if needed — no Zitadel apply required,
  per Wren's correction — so this is a low-stakes reversal if James ever wants a different name.
