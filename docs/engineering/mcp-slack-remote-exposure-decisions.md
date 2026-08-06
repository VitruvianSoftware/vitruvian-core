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

### 4. A completeness claim needs two differently-blind searches to agree, not one wider search

**Diff vs. file is the special case; "the search vs. the claim" is the general rule.**

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
carefully it's read.

**The stronger form, per Atlas (2026-08-06T20:10:22Z) turning the rule back on his own finding
before taking credit for it:** file-wide isn't automatically complete either — it's just a wider
search with its own blind spot. Atlas's first pass enumerated every method whose *signature* names
a channel and reported "two gaps." That scan cannot see a channel id arriving under a parameter it
didn't recognize by name. He re-enumerated from the opposite direction — every `api()` call site
that actually *passes* a `channel`/`channel_id` argument, independent of how the enclosing method's
signature reads — and the two scans agreed on the same two methods. They didn't agree by
redundancy: the signature scan would have missed a differently-named parameter, and the api-param
scan missed `createCanvas` outright on its own, because that method builds its params object by
assignment (`params.channel_id = channelId`) rather than as a literal, which a search for
`channel_id:` never matches. Only the second, differently-blind enumeration landing on the same
list is what turned "what I found" into "the complete set."

**General form: a completeness claim is a property of the search, not the object searched — "I
checked the whole file" narrows the blind spot, it doesn't remove one.** Diff-vs-file is a single
instance of the broader failure: the search you ran vs. the claim you made. Before asserting "these
are all of them" for anything that must hold across an entire class of call sites (every guarded
channel access, every escaped input, every place a credential could leak), get a second enumeration
built on a different mechanism than the first — grep-by-name and grep-by-usage, signature scan and
call-site scan, AST-based and text-based — and treat agreement between two differently-blind
searches as the actual evidence of completeness, not either search alone.

### 5. Restructuring away a completeness claim concentrates the risk into what's left — verify that, don't skip it

Wren's response to pattern 4 was to remove the need for the enumeration entirely: instead of
finding every call site that should have a channel guard, route all Slack egress through one
`api()` chokepoint with the guard as its first statement, so a call site literally cannot reach
Slack without passing through it. Verified structurally — only two `fetch()` calls exist in the
whole package, both inside `api()`. Beacon initially endorsed this as strictly better than the
enumeration discipline in pattern 4: *"when a completeness claim is load-bearing, prefer
restructuring so it doesn't need to be made."*

That endorsement was half right, and finding the other half cost a real bug. Atlas found that
`channelIdFromParams` **fails open**: a channel argument that isn't a string (an array, an object —
nothing validates tool-call argument types before the `as string` cast) makes the extractor return
`undefined`; `guardParams` reads `undefined` as *"this call isn't channel-scoped"* rather than
*"couldn't determine the channel"*; the value is still sent to Slack, coerced with `String(v)` on
the GET path. `{"channel_id": ["C0PRIVATE"]}` reaches Slack as `channel=C0PRIVATE` with the
allow-list never consulted — from an authenticated caller (bot membership still bounds it,
`SLACK_CHANNEL_IDS` no longer does). The chokepoint was real and did exactly what it promised:
every call reaches the guard. The defect had simply moved to live at the one place structurally
guaranteed to run — the guard's own logic — which nobody had re-verified with the same scrutiny
that went into proving the chokepoint existed.

**"Every call reaches the guard" and "the guard decides correctly" are different properties, and
making the first one structural does not establish the second — it concentrates all the remaining
risk into it.** Beacon's corrected version, stated for the record: **prefer restructuring so a
completeness claim isn't needed — then verify the thing the structure now depends on, because
you've concentrated the risk rather than removed it.** A chokepoint converts "did we find every
call site" into "is the one piece of logic every call site now shares correct," which is a smaller
and more tractable question — but it is still a question, not a conclusion, and it deserves the
same adversarial testing (malformed input, wrong types, the values an attacker would actually send)
that the enumeration it replaced would have needed. Apply this any time a fix for "coverage is
incomplete" is "route everything through one place": that's real progress, and the next step is
scrutinizing that one place harder, not treating the routing itself as the proof.

### 6. A value the code cannot interpret must never be treated as the permissive case

Per Atlas (2026-08-06T20:19:12Z): distinct from pattern 5, and it bit two people independently
within twenty minutes of each other on two different stacks in this build. Pattern 5 is about a
gap in *what's checked*; this one is about what happens when a check runs and the input can't be
parsed at all.

**Instance one, mcp-slack:** `channelIdFromParams` returning `undefined` for a non-string channel
argument, which `guardParams` then read as "not channel-scoped" — the permissive branch — rather
than "couldn't determine the channel," the restrictive one. Covered above as the pattern-5 worked
example; it's also an instance of this narrower rule.

**Instance two, `zitadel-apps-mcp-slack` (PR #1417):** `cfg.GetBool("projectRoleCheck")` routes
through `cast.ToBool`, which swallows any parse error and silently returns `false` for a string
`strconv.ParseBool` doesn't recognize. `projectRoleCheck` is the enforcement for decision 2 (only
the intended Zitadel subject may obtain a token) — `false` is Zitadel's permissive setting, issuing
tokens to any authenticated user. So `projectRoleCheck: "yes"` — a plausible, human attempt to turn
the check *on* — silently turned it **off**, while `pulumi up` reported success. Fixed at
`e9a86712`: unset still defaults to `false` deliberately (enabling before the role grant exists
locks out the first login), but a value that's *present and unparseable* now fails the apply with
a message naming what it governs, rather than being coerced.

**The rule: when coercing a value that governs a security-relevant branch, "I couldn't parse this"
is never the same outcome as either valid answer — and if your coercion function collapses the
two, that's the bug, independent of which branch happens to be the default.** Both instances share
the same shape: a general-purpose stdlib/utility coercion (`cast.ToBool`, `Boolean(x)`, a `typeof`
check that returns `undefined` on mismatch) has an implicit "give up gracefully" behavior, and that
behavior happened to land on the permissive side of a security decision. The fix is never "pick a
better default" — it's "distinguish 'absent' from 'malformed' from 'present and valid,' and treat
malformed as an error, not a default." Check this specifically wherever a config flag, an env var,
or a caller-supplied argument is parsed on the path to an allow/deny decision — a stray quote, a
`"yes"` where `"true"` was expected, or a wrong JSON type should fail loudly, not fail open.

**Addendum, per Atlas (2026-08-06T20:22:55Z), from sweeping the repo's other Pulumi stacks for the
same defect shape:** `infrastructure/pulumi/platform/repo_config` has the identical bug — bare
`cfg.GetBool` on `requireCodeOwnerReview` and `enforceAdmins`, both inheriting the same
`cast.ToBool` fail-open-to-false — and unlike the two instances above, **this one is live** and
applies via CI (`_repo-config-apply.yaml`), governing branch-protection approvals on `main`. Not
fixed here; tracked separately, its own PR and review.

**The sharper form this adds: the flags most exposed to this defect are the ones documented as
"flip later."** `requireCodeOwnerReview` carries a comment reading *"flip to true once a second
reviewer exists"* — which means the moment someone types the value by hand is necessarily months
after the decision was made, by someone who wasn't there for the original context and has no
reason to suspect `"yes"` behaves differently from `"true"`. `projectRoleCheck` (pattern 6's
original instance) has the identical shape — a flag deliberately shipped `false` with a written
plan to flip it once a precondition clears. **A boolean config value that ships with a comment
saying "someone will change this later" is a higher-priority audit target for this class of bug
than one set once and left alone**, precisely because the person who eventually edits it is
reconstructing intent from a comment rather than carrying the context that produced it.

### 7. A check that serves two purposes should say so, or the second purpose dies in a refactor that looks like a simplification

Per Beacon (2026-08-06T20:41:27Z): `looksLikeJwt()` in mcp-slack's auth path is a string-split
and a regex that rejects an obviously-malformed bearer token before any network call or
cryptographic work. Wren wrote it as a diagnostic — so a garbage token gets a self-describing
"this isn't a JWT" error instead of a generic 401. Reviewing the rate-limiting gap, Atlas traced
the rejection path and found it does something Wren hadn't named as a goal: because it runs before
`jwtVerify` and before JWKS lookup, it makes a flood of junk requests cheap to reject — CPU only,
no I/O, no crypto — which is load-bearing for the endpoint's resistance to a trivial DoS on a
public, unauthenticated-until-parsed path. Neither purpose was written down as the reason for the
check; both were true, and only one was intentional at the time.

**The risk this creates: a later change that looks like a pure simplification can silently remove
a property nobody documented.** Someone optimizing the auth path and seeing a diagnostic-only
regex ahead of the "real" verification could reasonably fold `looksLikeJwt`'s check into
`jwtVerify` itself — correct by the diagnostic's own stated purpose, and a regression by the
purpose nobody wrote down. The code would look cleaner and be worse.

**Rule: when a check earns its keep for more than one reason, name all of them at the check
itself — not just the one that motivated writing it.** A comment reading "cheap rejection of
malformed input before any I/O — also serves as DoS resistance on the public path" costs one line
and removes the trap. Apply this any time a review (like Atlas's here) surfaces a benefit the
author didn't intend: the fix isn't just gratitude, it's writing the second purpose into the code
before it has a chance to be refactored away by someone who only ever saw the first one.

**Sharpened by Atlas (2026-08-06T20:41:53Z), the same day:** this isn't only about an author who
knew a check served two purposes and failed to document the second one — `looksLikeJwt` didn't
have that author. Wren wrote it for one reason; Atlas found the second reason later, while tracing
something unrelated, and neither of them knew about it at the point the code was written. **The
rule has to cover the case where nobody knew there was a second purpose to document:** when a
reviewer discovers a check doing work its author never intended, the obligation to write it down
at the check falls on whoever discovered it, not on the original author — because the next
refactor will only preserve the reason that's actually written there, regardless of who found it
or when.

### 8. A correct, tested primitive doesn't help the call site that quietly doesn't use it

Per Scout (2026-08-06T20:42:35Z), reading the frozen head cold rather than following the thread's
own trail: `listChannels()` re-parses `SLACK_CHANNEL_IDS` straight from `process.env`
(`index.ts:621`) with its own inline splitting, instead of calling the already-built and
already-tested `parseChannelIds`/`channelGuard` — the only `process.env` read anywhere in the
module outside `config.ts`. Demonstrated, not asserted: fed `"C1,C1,,C2, ,C3"` through both paths —
the tested parser normalizes it to `['C1', 'C2', 'C3']`; `listChannels()`'s own inline split
iterates `['C1', 'C1', '', 'C2', '', 'C3']`, untouched by the trimming and dedup the *tested* path
exists specifically to provide. Not a security bypass on its own (`SLACK_CHANNEL_IDS` is
operator-set config here, not caller input), but the mechanism is exactly the one that would make
it one somewhere else: a boundary-relevant primitive built correctly and covered by tests, quietly
bypassed by a second, ad hoc implementation of the same logic three lines away.

**Beacon's generalization across the build's five other defects (2026-08-06T20:44:33Z):** every
one of them — the two unguarded methods, the fail-open extractor, the `cast.ToBool` fail-open (in
two independent stacks), the malformed-`WWW-Authenticate` quoting — shares this shape at bottom. A
correct piece of logic exists and, in most cases, is well-tested. The defect never lives in that
logic; it lives in a *second* place that was supposed to use it and either doesn't, or
reimplements a weaker version of it. **Six defects tonight were not six unrelated bugs — they were
one pattern instantiated six times: trust the primitive, then go looking for who's actually
calling it.**

**Rule: when you've verified a security- or correctness-relevant primitive is right and tested, the
next question is never "is it right" again — it's "who else in the codebase does the equivalent
thing without going through it."** Grep for parallel implementations of the same parsing, the same
validation, the same coercion (a second `.split(',')` on the same env var, a second regex for the
same shape, a second inline type check) before trusting that a well-built, well-tested module has
actually closed the class of bug it was built to close. A tested primitive with an untested,
parallel caller is not partial coverage of the problem — it's a false sense that the problem is
covered at all.

### 9. When the artifact is a security configuration and the action is irreversible, wait for the specialists before sending anything

Per Beacon (2026-08-06T20:54:14Z), owning it as a process failure rather than a code one: while the
team was iterating live on which Slack app scopes the new app should carry (dropping `im:history`/
`mpim:history`, then `users:read.email`, each correction genuinely right in isolation), Beacon
relayed each successive version to James as it was found — three scope lists in five minutes — so
he could act on it while the branch sat frozen on the CI outage. Aegis's design-level review then
found a fourth, more serious problem with the same scope set (`slack_get_users` enumerating the
entire workspace directory, unbounded by any control built that evening — see above) before the
third relayed version had even been acted on.

**The asymmetry that made this a mistake, not just churn:** the team's own artifact (a scope list in
a channel) is trivially revisable — post a correction, nobody's harmed. **James's action on that
artifact is not** — creating and installing a Slack app, then discovering it needs narrowing, costs
a second app-and-token cycle in the live workspace. Relaying an in-progress design to someone who
will act on it irreversibly treats a mutable draft and a one-way door as though they were the same
kind of thing.

**Rule: when what you're about to send is a security configuration (a scope list, a permission set,
an IAM policy, a firewall rule) and the recipient's response to it is irreversible or expensive to
undo, hold it until the people with the relevant expertise have finished reviewing it — do not send
draft N so the recipient has something to do while draft N+1 is still being found.** The fix isn't
reviewing faster or relaying more carefully; it's recognizing that some artifacts should never be
partially relayed at all, because the value of "giving the human something to do" is negative once
what they do with it can't be cheaply reversed. Apply this specifically to any handoff where the
team is still actively finding problems with the artifact and the recipient's next action is a
click, an apply, or an install rather than a re-readable message.

### 10. A boundary built in one layer needs to be designed in every layer that could hold it — weakest first

Per Aegis's design-level review (2026-08-06T20:55:43Z), answering the question the whole build had
been implicitly avoiding — not "does the implementation match the design" but "is the design
right." mcp-slack has (at least) three places a control over what the endpoint can reach could
live, from weakest to strongest:

| | Layer | Enforced by | Survives | Built, as of this review |
|---|---|---|---|---|
| **L3** | `SLACK_CHANNEL_IDS` allow-list | this process's own code | our own correctness | to a high standard — nine defects found and fixed here |
| **L2** | who may call at all | Zitadel `projectRoleCheck` | an apply landing right | off, single-instance |
| **L1** | Slack bot scopes | Slack itself | *everything*, including a leaked token | inherited from the local stdio tool, never re-derived for this use |

Nine of this build's defects were all found and fixed in L3 — real, worth finding, and still the
weakest layer available, for two properties that hadn't been named before this review:

- **L3 only binds channel-shaped calls.** A control keyed on a channel parameter cannot, by
  construction, say anything about a call that doesn't carry one — see the `slack_get_users` gap,
  above. No amount of care inside the guard changes what class of call the guard can see.
- **L3 is void the moment the credential leaves the process.** The bot token lives in the pod's
  environment. Anyone who obtains it by any means — pod exec, a log dump, an unrestricted egress
  path, a future bug — holds the bot's full reach, unbounded by anything this repo's code does,
  because the allow-list is a property of the code, not of the token.

**L1 is the only layer that holds when the code is wrong, and it's the one that was inherited
rather than designed** — see the scope table above, narrowed only after this review. L2 was built
but shipped off by necessity (the bootstrap-ordering problem) with no second enforcement point,
until `OIDC_ALLOWED_SUBJECTS` closed that gap (below).

**Rule: for any system exposing a boundary, enumerate every layer capable of holding that boundary
— weakest and least trustworthy first, most authoritative last — before declaring the boundary
"designed."** A team can pour real scrutiny into the weakest layer (as this one did, to a high
standard) and still have an undesigned system, because scrutiny inside one layer says nothing about
whether the other layers were considered at all. The question to ask isn't "did we test this
control correctly" — it's "what layers could hold this boundary, and did we design for all of
them, or only for the one we happened to be looking at."

### 11. Findings that are each individually "doesn't reach us" can compose into one that does

Per Beacon (2026-08-06T20:58:17Z), on Atlas's Zitadel exposure analysis. Two open questions —
whether the instance permits self-registration, and whether a different OIDC client in the org can
request this project's audience scope — were each assessed independently and each, alone, judged
insufficient to reach mcp-slack: self-registration alone still requires a token scoped to this
project, which needs a client that can request it; a permissive audience alone still requires an
account to authenticate with, which registration being closed would prevent. **Together, they
compose into a live path:** anyone on the internet registers, authenticates through some other
client in the org capable of requesting this project's audience, and holds a token this server
accepts — during any window where caller identity is unenforced.

**Nobody had checked for this because each question was correctly closed on its own, and closed
questions don't get revisited against each other.** Every pattern this build produced before this
one is about a single claim, made and later found wrong or incomplete on its own terms — a
completeness claim, a parse-fallback default, an undocumented second purpose. This is different in
kind: **two independently-true, independently-insufficient findings, neither of which is a defect
by itself, can multiply into a real exposure that neither review would surface alone.**

**Rule: when a system's safety argument rests on multiple independent conditions each being
false (or each being narrow), explicitly check the conjunction, not just each condition in
isolation.** After closing a finding as "doesn't reach us, because X is also required," ask what
else would need to be true for X itself to be satisfied — and whether anything already known, or
still open, satisfies it. A go-live review that closes N findings independently has not yet checked
whether any two of those N compose into an N+1th.

## The six decisions

| # | Decision | Final answer | Rationale |
|---|---|---|---|
| 1 | Tenancy | **Single-tenant.** One deployment, one set of Slack tokens; every connected agent acts as James's Slack identity. | `src/index.ts:802-808` reads tokens once at process start — one identity per process. Multi-tenant needs per-request token resolution and a token store: a rewrite of the server's core, not a transport addition. |
| 2 | Who may connect | **Zitadel-native subject, no Google social login.** Atlas confirmed no social-login IdP is configured on the Zitadel instance (`gitops/argocd/platform/zitadel/applicationset.yaml`); adding one is new config work that would put Google in the trust chain directly in front of the Slack workspace, for no PoC benefit. **Identity mechanics settled 2026-08-06T20:45Z:** James's Zitadel user is **not** a Pulumi resource — human accounts mutate outside IaC constantly (password, MFA, profile), and declaring one would need `IgnoreChanges` over most of the resource, deliberately reproducing the `accessTokenType` drift problem (pattern 6) on an identity. James creates his own user via the Zitadel console (he's currently only known to be signed in as the bootstrap admin, `admin@vitruvian.auth.ipv1337.dev`, and hasn't confirmed a personal account exists); the resulting user ID becomes stack config, and only the project-scoped `zitadel.UserGrant` in `zitadel-apps-mcp-slack` is code — it dies with the project, as it should. | Keeps the Gemini test account (client-side) and the Zitadel subject (gate-side) cleanly separate — conflating them was an early gap in the thread that Beacon caught. Keeping the human identity out of Pulumi keeps Zitadel as the system of record rather than creating a second, drifting one. |
| 3 | Slack write credential (was bot-only/read-only; reopened by decision 6) | **Option A: bot-token-only write via `chat:write` (no `chat:write.public`), never the user token.** No user token enters the cluster. Writes on the HTTP path route through the bot token; stdio keeps user-token routing unchanged. **Mechanism updated 2026-08-06T20:50Z: a new, dedicated Slack app is now the recommended way to deliver this, not reinstalling the existing "Vitruvian Slack MCP" app.** See "Option A" section below — the ladder, the reordering, and why the new-app rung is now preferred on more than cost. | See "Option A" section below — the full resolution and the reordering rationale. |
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
**bot-token-only writes via `chat:write`, never the user token.**

| Option | Delivers #6 | Cost |
|---|---|---|
| **A. Bot-token `chat:write` — chosen** | Yes | Posts appear as the app, not as James; keeps the user token out of the cluster entirely |
| B. Ship the user token, cap the remote tool list | Yes | James's personal token on a public endpoint; posts as James; the capped-tool-list boundary is a hand-maintained filter that has to hold indefinitely now that the deployment may be permanent |
| C. Read-only PoC, defer write | No | Doesn't meet the scheduled-reports goal that motivated decision 6 |

**Mechanism — reworked 2026-08-06T20:47-20:52Z. A new, dedicated Slack app is the recommended way to
deliver Option A, not reinstalling the existing "Vitruvian Slack MCP" app James's local stdio
tool already uses.** The choice started as a single path (reinstall the existing app) and was
reordered into a three-rung ladder once the team reasoned through what reinstalling actually
inherits:

| Rung | Mechanism | Delivers #6 | Note |
|---|---|---|---|
| **1 — chosen** | **New Slack app**, scoped narrowly from creation, `chat:write` included | Yes | James owns it outright; no admin rights on the existing app needed to create one (workspace app-creation/install policy pending confirmation) |
| 2 — fallback | Reinstall the existing app with `chat:write` added | Yes | Needs collaborator/admin rights on the existing app, which James has confirmed he doesn't have on the workspace side; unconfirmed whether he holds narrower app-collaborator rights |
| 3 — fallback | Read-only PoC | No | Only if neither 1 nor 2 is available |

**Why rung 1 beats rung 2 on more than cost** (the reasoning that reordered the ladder — record this
where a future "why not just reinstall" question would look):

- **Blast radius, categorical rather than probabilistic.** The existing bot has accumulated
  membership in whatever DMs, group DMs, and private channels it's been invited to over its
  lifetime — un-inventoried, and un-inventoriable from outside (`im:read`/`mpim:read` aren't on its
  scopes). Reinstalling it inherits that membership as-is. A new app's bot starts in zero
  conversations; its reach becomes exactly the channels James deliberately invites it to. That
  guarantee is *probabilistic* under rung 2 (it holds only as long as membership is managed
  carefully, forever) and *categorical* under rung 1 combined with a narrower scope set (below) —
  Slack refuses the operation outright, independent of membership or the allow-list.
- **Independent revocation.** A new app means the cluster's `SLACK_BOT_TOKEN` and James's local
  stdio token are different Slack apps entirely — different credentials. If the public endpoint is
  ever compromised, misbehaving, or just needs to be killed in a hurry, James revokes the new app's
  token and his local Claude Code keeps working. Under a shared app, the only lever to cut off the
  public endpoint is a token his laptop also depends on — emergency shutdown becomes self-inflicted
  denial of service on the trusted path, which is exactly the moment hesitation is most costly. A
  containment control you'd think twice about pulling isn't much of a containment control.
- **Eliminates a same-day coordination hazard entirely, rather than sequencing around it.** The
  reinstall path (rung 2) issues a new `xoxb-` and kills the old token immediately
  (`token_rotation_enabled: false`), so James's local config breaks until updated — a handoff that
  had to be sequenced deliberately (James updates local, *then* Atlas re-seals the cluster). Under
  rung 1 the existing app is never touched, so that hazard doesn't need managing — it doesn't exist.
- **Marginal infra cost is ~zero.** Both rungs re-seal the cluster's sealed-secret and issue a new
  `xoxb-` token; `SLACK_TEAM_ID` is unchanged either way, since it identifies the workspace, not the
  app — worth stating so nobody re-derives it from the new app's install and gets it right by
  accident, which would teach the wrong model. The only real cost of rung 1 over rung 2 is James
  re-inviting the bot to his target channels by hand — and that manual step is what *creates* the
  categorical guarantee above, not overhead on the way to it.

**⚠️ Decision property, not a footnote — record where a future consolidation would be proposed:**
**the cluster path and the local stdio path are on separate Slack apps deliberately.** Independent
revocation exists *only* as a side effect of that separation; nothing in the code or chart
expresses it as a requirement. A later "simplification" that merges both onto one app — which will
look like sensible tidying to whoever proposes it — silently removes the ability to kill the public
endpoint without also breaking James's local tool, **and the loss is invisible until the moment
someone actually needs to revoke, which is the worst possible moment to discover it.** Same shape
as pattern 7 (`looksLikeJwt`'s undocumented second purpose), landing during an incident rather than
a refactor review.

**Scope set for the new app — narrowed from the existing app's set, not copied.** The existing
app's scopes were designed for a local stdio tool with unrestricted reach; several don't correspond
to anything the HTTP tool list actually exposes, and copying them by default was itself an instance
of pattern 8 (inherited from a different context, never re-checked against the current
requirement — caught in this thread eight times now). Checked against the eleven tools the HTTP
path advertises after filtering:

**Settled 2026-08-06T20:56Z** (sent to James by Beacon only after Aegis, Wren, and Atlas had all
signed off on the same list — the first list this build sent him that specialists agreed on before
it left, per pattern 9):

| Keep | Why |
|---|---|
| `channels:read`, `channels:history` | Public channel list/read — used |
| `pins:read`, `bookmarks:read` | The two list tools — used |
| `users:read` | Single-user profile lookup only (`slack_get_user_profile`) — resolves a `U…` id surfaced from allow-listed channel history. Bulk enumeration (`slack_get_users`/`users.list`) is withheld from the HTTP tool list, below — the scope alone was not sufficient protection. |
| `chat:write` | Decision 6's write requirement |
| `groups:read`, `groups:history` | **Off by default, not James's call to enable in advance.** Per Aegis: a private channel entering the allow-list should be a deliberate decision with its own line when James actually wants one, not a capability granted speculatively "in case." Being wrong in the direction of omitting costs one reinstall; being wrong in the direction of including costs an unbounded-by-anything-but-the-allow-list private-channel surface. |

| Drop | Why |
|---|---|
| `im:history`, `mpim:history` | Nothing in the HTTP tool set reads a DM or group DM. Dropping them makes DM/group-DM access categorically impossible on this credential — Slack refuses regardless of membership or allow-list — rather than merely unlikely. Retires the DM half of the membership-inventory question by construction (see below), not by policy. |
| `users:read.email` | `slack_get_user_profile` (`slackClient.ts:206-211`) succeeds without it — Slack just omits the email field. Nothing in the tool set requires it; its only effect is putting workspace members' emails into responses. **Fails silently if omitted, not loudly** — unlike the DM scopes, an absent `users:read.email` produces a 200 with a missing field, not a `missing_scope` error, so if email is ever needed later the symptom is a silently absent field, worth a code comment if this scope is ever reconsidered. **General rule, per Wren, self-corrected after over-generalizing once:** whether a narrowed scope fails loudly or silently depends on whether it gates the *call* (loud — `missing_scope`) or gates a *field on an otherwise-successful call* (silent — the field is just absent). Check which shape applies before assuming a narrow scope is safe to try. |

**The design gap underneath both scope questions, found by Aegis's design-level review (2026-08-06T20:52-20:55Z) — the most significant finding of this build, because it is the first one outside every boundary constructed so far, not a bug inside one:**

`slack_get_users` (`users.list`) and `slack_get_user_profile` (`users.profile.get`) carry **no channel parameter at all** (`slackClient.ts:203,207`). `readChannelParam` correctly returns `{kind: "absent"}` for both — there is no channel to check — and `assertParamsAllowed` correctly passes them through, because that is the right behavior for a call that isn't channel-scoped. Neither tool is in `USER_TOKEN_ONLY_TOOLS`, so both were advertised and dispatchable over HTTP. The consequence: **`slack_get_users` returned the entire workspace member directory to any authenticated caller**, unbounded by `SLACK_CHANNEL_IDS`, bot channel membership, or which rung of the ladder above is chosen — because `users.list` is **workspace-scoped, not channel-scoped or membership-scoped**. A new app's bot in zero conversations still returns the full directory on its very first call. `projectRoleCheck` doesn't help either — it restricts *who* may call, not *what* a valid call reaches.

**Every control built earlier tonight (the channel allow-list, the credential-boundary pattern, the new-app blast-radius argument) is channel-shaped. This tool is not channel-shaped, so none of those controls bind to it.** That is why a design-level review (Aegis's brief: "is the boundary correct," not "does the implementation match the design") caught what nine rounds of code review, testing, and adversarial completeness-checking did not — every prior defect this build found was *inside* the channel boundary; this was the first one *outside* it.

**Fixed and shipped, `922e9146` on #1418, independently verified by both Aegis and Beacon at the file
level.** `slack_get_users` is withheld from `HTTP_WITHHELD_TOOLS` (`tools.ts:531`), which feeds both
`ListTools` and the dispatch-time name check (`index.ts:68,80`) — withheld from advertisement *and*
from invocation by name, not just hidden from the list. `slack_get_user_profile` correctly stays.

**Wren enumerated every method in the module with no channel parameter — the durable artifact from
this finding, worth more than the one-line fix:**

```
getUsers               users.list                   ← was reachable on HTTP; now withheld
getUserProfile         users.profile.get             ← reachable on HTTP; legitimate, kept
searchMessages         search.messages                user-token, already refused
searchFiles            search.files                   user-token, already refused
editCanvas             canvases.edit                   user-token, already refused
lookupCanvasSections    canvases.sections.lookup       user-token, already refused
deleteCanvas           canvases.delete                 user-token, already refused
```

**Five of the seven were already refused — by `USER_TOKEN_ONLY_TOOLS`, a control aimed at something
else entirely (bot/user credential separation, decision 3), not at this class of gap.** That's the
residual risk stated exactly right, per Wren: being saved by an unrelated control is the definition
of a gap that isn't actually closed. If the user token ever returns to the HTTP path, or a canvas
tool ever gains a bot-token route, five refusals evaporate silently, because nothing in the code
records that they were load-bearing for this reason. The fix Aegis asked for and Wren is carrying:
a comment at `HTTP_WITHHELD_TOOLS` stating *why* each entry is there, not just that it is.

**Consequence for the bot-membership-inventory open item (was: "someone with Slack workspace admin
should inventory the bot's private-channel and DM membership before the endpoint goes public"):**
retires **only for the exposed HTTP path** under rung 1 — a new app's bot starts with zero
membership and, once `im:history`/`mpim:history` are dropped, cannot express a DM read at all. It
does **not** retire for stdio: James's local Claude Code keeps using the existing app with its
accumulated, un-inventoried membership. That inventory question stays open for the local tool; it
does not apply to anything reachable from the public internet.

**What Option A requires under rung 1, in order:**

1. James creates a new Slack app in the abrial workspace with the scope set above (confirm first
   whether workspace policy lets members create apps, and separately whether installing one needs
   admin approval — a created-but-uninstallable app spends the round trip for nothing).
2. Invite the new app's bot to every channel it needs to read and write — `chat:write` (and
   history/info/thread-reads) only work in channels the bot is a member of, a second Slack-enforced
   boundary stacked on the `SLACK_CHANNEL_IDS` allowlist.
3. Atlas seals the new `xoxb-` token into the cluster's sealed-secret — independently, with no
   sequencing dependency on James's local setup, since the existing app (and his local config) is
   never touched.
4. On the code side (Wren's transport PR): `postMessage`/`replyToThread`/`updateMessage` route
   through the new app's bot token **only on the HTTP path**; stdio keeps routing through the
   existing app's user token exactly as today — `manifest.json` continues describing the existing
   app, with the new app's scopes documented alongside it, not editing over it.

**If rung 1 turns out unavailable** (workspace blocks member-created apps, or blocks installing
them without admin approval), fall back to rung 2's mechanics — reinstalling the existing app with
`chat:write` added — which inherits the reinstall-coordination hazard and the un-inventoried
membership blast radius described above, and needed a deliberate sequencing step: update James's
local stdio config first, confirm Claude Code still works, *then* hand the new token to Atlas to
re-seal — since that hazard doesn't exist under rung 1 but returns under rung 2.

Bot-attribution (posts appearing as the app rather than as James) is the one piece of Option A that
was a product call, not an engineering one. **Resolved 2026-08-06T20:36Z, direct from James (DM to
Beacon):** yes, posts go out as the app — and he asked for a further, related feature: Slack
readers should be able to tell which human requested a given app-posted message. See "Message
attribution," immediately below — **this is active, in-scope work, not a deferred design note.**

## Message attribution — active requirement (added 2026-08-06T20:36Z, corrected into scope 20:46Z)

James's exact request, answering Beacon's bot-attribution question: *"yes for spark's slack write
posts as the app but would it be possible to mention on behalf of who so users will know?"* — i.e.
`Requested by James Nguyen via Gemini Spark` on posts, replies, and edits made through the HTTP
path. This was briefly treated as a design note deferred to a hypothetical multi-tenancy future
(the single-caller argument for deferring it was wrong — James's reason is that **Slack readers**
should know who's behind an app-posted message, which holds regardless of how many callers the
deployment has). It is Wren's to build now, not later.

**The design constraints this must be built against, worked out before the (corrected) scope call
and still binding:**

- **The attributed name must never be sourced from a token claim the subject can edit.** Zitadel
  display-name claims are user-editable; rendering one verbatim into an app-posted message would
  let the requester write their own provenance line — harmless at one authorized subject today,
  a spoofing vector ("Requested by Security Team") the moment decision 2 ever widens. Source the
  name from a **deploy-time mapping** (`sub` → display name, configured alongside the deployment)
  instead — a one-entry mapping at today's single-tenant scale, extended per-subject if decision 1
  ever changes. `sub` is specifically the claim to key on because it's the one claim the subject
  cannot edit; `name`/`email`/`preferred_username` are profile fields the user changes at will, and
  the failure mode to guard against isn't someone forgetting the mapping — it's someone later
  "simplifying" it to read the display name straight off the token, which turns provenance into
  self-assertion and looks like a cleanup. An unrecognized subject gets no attribution line rather
  than one it authored.
- **Correction, per Aegis (2026-08-06T20:55:43Z) — this is not an addition to the design, it's a
  correction to how it must be understood: attribution is not a security control, and it must
  never be documented or reasoned about as one.** The caller controls the message `text`. Nothing
  in this design stops a caller writing `Requested by Someone Else` directly into the message body
  — the deploy-time mapping only governs the server-appended attribution line, not the content a
  caller supplies. **The line proves a message came from this endpoint. It proves nothing about who
  asked, to a reader who doesn't already trust the endpoint's own attribution mechanism over
  arbitrary body text.** Build consequence: render the attribution as a **server-appended Block Kit
  `context` block**, never string-concatenated into `text`. A `context` block is visually and
  structurally distinct from the message body, so a body-text forgery of "Requested by ..." stays
  distinguishable from the real thing at no extra cost — and it's what keeps the
  unrecognized-subject-gets-no-line rule meaningful, which plain string concatenation would quietly
  undermine (a forger could just write the line themselves).
- **Don't widen OAuth scope to carry the name.** Requesting `profile`/`email` to get a name claim
  onto the token grants Spark real additional capability for a cosmetic string; the deploy-time
  mapping needs no extra scope at all.
- **Don't call out to Zitadel per post.** A userinfo lookup on the write path would put the IdP in
  the critical path for every message and reintroduce the availability coupling readiness was
  deliberately built to avoid (see the health-check design in `httpTransport.test.ts`).
- **`updateMessage` must re-render the attribution block on every edit, not just be allowed to
  keep it.** An edit that silently drops the block is worse than never having attribution — the
  message stays posted, still app-authored, now with the requester erased. Re-rendering on edit
  needs to be the default behavior, not an opt-in a caller has to request.
- **stdio is out of scope for this feature.** No `authInfo` exists on that transport, and on stdio
  the write already goes out as the human — an attribution line there would be redundant on a
  message the reader already knows was posted by that person directly.

## Go-live gate — layers beyond L3 (added 2026-08-06T20:56-20:58Z, per Aegis's design review)

Separate from and layered on top of Phase 1's code-merge gate (which does not reopen for any of
this). None of the following blocks merging the transport PR; all of it blocks the endpoint being
publicly reachable. Restructured, per Beacon, so review has something written to check against
rather than chasing code that doesn't exist yet — Atlas writes to this list, Aegis reviews against
it, not the other way around.

**L2, doubled: `OIDC_ALLOWED_SUBJECTS`.** `projectRoleCheck: true` (decision 2's Zitadel-side
enforcement) can't be enabled before James's role grant exists, which can't exist before he creates
a Zitadel user — a hard bootstrap ordering that left a window where the endpoint would be publicly
reachable with caller identity unenforced. Rather than accept that window (bounded only by
discipline — see the standing rule below), the team added a second, independently-testable
enforcement point: a required, fail-closed `OIDC_ALLOWED_SUBJECTS` config, checked against the
verified `sub` claim, same shape and same `MissingAllowlistError` treatment as `SLACK_CHANNEL_IDS`.
Built as its own PR after the transport PR merges (not folded in — that PR is frozen with three
independent reviews against one head, and reopening it costs a schedule with nothing to gain while
both are outage-blocked anyway). **Does not replace `projectRoleCheck: true`** — the point of the
L1/L2/L3 framework above is that the same boundary held in two independent places is stronger than
either alone, and this is L2 in two places rather than one.

**Design requirement carried into that PR, continuing the self-describing-error pattern already
established for `AudienceMismatchError`:** the rejection must print the `sub` it actually received.
The argument for `OIDC_ALLOWED_SUBJECTS` over accepting the bootstrap window rests on "a wrong
assumption about `sub`'s shape fails closed — James gets a 403 on his own first login and reads
the true value off the log." That claim is only true if the code actually prints the value; absent
that, a fail-closed *unknown* quietly becomes a fail-closed *mystery*, indistinguishable from any
other misconfiguration. The failure has to carry its own fix, the same discipline that makes
`AudienceMismatchError` print the audience actually presented rather than just refuse.

**Standing rule, adopted verbatim from Aegis's fallback proposal even though `OIDC_ALLOWED_SUBJECTS`
makes it belt-and-braces rather than the plan: no real channel enters `SLACK_CHANNEL_IDS` while
the endpoint is publicly reachable and caller identity is unenforced.** Windows are short until an
apply fails.

**Phase 2b acceptance criteria — the runtime half of the boundary, which exists in none of #1416,
#1417, or #1418 as of this writing (there is no `mcp-slack/deploy/` and no gitops reference yet;
this is unwritten work, not an unreviewed gap):**

1. **Tunnel ingress scoped to the MCP path only; `/health` stays in-cluster.** Kubelet probes hit
   the pod IP directly and never traverse the route, so nothing needs `/health` reachable from the
   internet — an unauthenticated 200 on a public hostname is a free liveness oracle for anyone
   scanning. This is a **routing property, not a server property**: the fix is an `HTTPRoute`
   matching only the MCP path (the cluster already does this elsewhere), not a second listener or
   any code change. `/health` keeps returning exactly `{"status":"ok"}` — health endpoints accrete
   diagnostic fields over time, and each addition individually looks reasonable while turning an
   in-cluster probe into a reconnaissance response if the route is ever widened.
2. **Egress `CiliumNetworkPolicy`** scoped to `slack.com:443` and the Zitadel JWKS host, nothing
   else. No workload on this cluster currently has egress restricted (zero `CiliumNetworkPolicy`
   resources exist in `gitops/` today), and the one prior attempt (on `argocd-image-updater`) was
   reverted because it needed apiserver access the policy didn't correctly grant — moot for
   mcp-slack, which needs no apiserver access at all, making it a better first candidate than the
   workload that failed. **`toFQDNs` requires an explicit DNS-proxy rule or it silently matches
   nothing** — the same fail-open shape as the reverted attempt, worth getting right the first time
   given the precedent.
3. **Rate-limit rule at the Cloudflare edge**, since the entire auth path currently runs before
   anything throttles a request.
4. **Pod hardening**: sealed bot token (already decided — bot token + team ID only, no user
   token in-cluster), non-root, read-only rootfs, resource limits, image by digest, a
   **sustained-5xx alert** (a JWKS outage leaves the pod `Ready` while every call fails — passing
   readiness and being useless are different states, and nothing currently distinguishes them),
   `terminationGracePeriodSeconds` + `preStop` paired with the app's own `SIGTERM` handler.

**Two go-live blockers, unowned by this record because they're bigger than mcp-slack — noted here
only because `OIDC_ALLOWED_SUBJECTS`'s value depends on them, not because this doc is where they
get resolved.** Whether the Zitadel instance permits self-registration, and whether a different
OIDC client in the org can request this project's audience scope, both bear on how exposed the
bootstrap window actually is (see pattern 11 — the two compose). **Self-registration, if enabled,
is a platform-wide Zitadel exposure question, not an mcp-slack one** — Zitadel is the SSO for the
whole homelab, `oauth-user-inspector` already sits behind it, and it would be true regardless of
whether this PoC existed. It's being raised as its own standing platform question elsewhere, not
tracked as part of this build's gate. What *is* specific to this build: whichever way both
questions resolve, `OIDC_ALLOWED_SUBJECTS` is the one control in the chain that doesn't depend on
either answer, because it's enforced in this process against a value in this chart.

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

## What's still James's to do (updated 2026-08-06T20:46Z)

1. ~~Bot-attribution yes/no~~ — **Answered, 20:36Z (DM to Beacon): yes**, posts go out as the app —
   and James asked for the further attribution feature specified above, which is now active work.
2. **Slack admin session — at risk, not yet actionable.** James has confirmed **no admin rights on
   the abrial workspace**, which puts step 2 of Option A (reinstalling the app to add `chat:write`)
   in doubt — see the ⚠️ flag on decision 3, above. Outstanding: whether James holds a narrower
   *app-collaborator* role that's sufficient for a reinstall even without workspace admin. If
   neither, Option A cannot execute as specified and decision 3 reopens to Option B or C.
3. ~~Zitadel 30-second login check~~ — **Superseded.** The design changed: James's Zitadel user is
   no longer a Pulumi resource (see decision 2, above). His outstanding action is now to create his
   own Zitadel user via the console — he's currently signed in only as the bootstrap admin
   (`admin@vitruvian.auth.ipv1337.dev`) and hasn't confirmed whether a personal account already
   exists. The resulting user ID becomes stack config for the `zitadel.UserGrant` binding him to
   `mcp-slack-user`.

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
