# Pulumi Cloud: one update at a time, account-wide

## The limitation

Our Pulumi Cloud backend is an **individual account** (`ipv1337`). Individual
accounts permit exactly **one running update across the entire account** — not
one per stack, not one per project. While any stack is updating, an update to
*any other* stack is rejected immediately:

```
error: [409] Conflict: You have a running update for the stack 'pulumi_tabula_web/development'.
Individual user accounts do not support concurrent updates. Create an organization to have
concurrent updates, wait for this update to complete, or run
`pulumi cancel -s pulumi_tabula_web/development` to cancel the ongoing update.
```

Note what the message names: the stack holding the lock is a **completely
unrelated one**. A failure here says nothing about the stack you were deploying.

## What it cost us

# Publishing to npm: trusted publishing (OIDC)

## Why there is no npm token any more

Every npm release from this org failed from **2026-05-07** onward. The stored
credentials return `E401 Unauthorized` against the registry — verified directly
against all four values held in Bitwarden's `npm` item.

Minting a replacement is a dead end rather than a fix. GitHub
[deprecated 2FA-bypass granular access tokens on 2026-07-08](https://github.blog/changelog/2026-07-08-npm-install-time-security-and-gat-bypass2fa-deprecation/):

| phase | when | effect |
|---|---|---|
| 1 | early August 2026 | bypass-2FA GATs can no longer skip 2FA for account/package management |
| 2 | ~January 2027 | they lose **direct publishing**; only read + staged publish awaiting human 2FA |

So the supported paths are **trusted publishing (OIDC)** — what we use — or
staged publishing with a human approval step.

## What the workflows now do

Publishing authenticates with a short-lived OIDC token minted by the runner and
exchanged with npm. There is **no long-lived npm secret anywhere** — not in
GitHub, not in Bitwarden.

Each publishing workflow:

1. declares `id-token: write` (without it the runner cannot mint the token);
2. upgrades npm and **asserts `>= 11.5.1`** — Node 22 bundles npm 10.x, and an
   npm too old does not say so, it quietly looks for a token that is no longer
   there;
3. **strips the `_authToken` line** that `actions/setup-node` writes, then
   asserts it is gone.

Step 3 is the non-obvious one. `setup-node`'s `registry-url` writes
`_authToken=${NODE_AUTH_TOKEN}` into its generated `.npmrc`. With no token set
that expands to an **empty value**, npm concludes auth is already configured,
never performs the OIDC exchange, and fails with `ENEEDAUTH` — which reads like
a credential problem rather than the configuration problem it is. See
[actions/setup-node#1551](https://github.com/actions/setup-node/issues/1551) and
[npm/documentation#1960](https://github.com/npm/documentation/issues/1960).

## The part that must be done on npmjs.com

Trusted publishing is configured **per package**, and CI cannot do it. For each
package, under Settings → Trusted Publisher:

| field | value |
|---|---|
| Organization or user | `VitruvianSoftware` |
| Repository | the **mirror** (`mcp-slack`, `pulumi-library`) — *not* `vitruvian-core` |
| Workflow filename | `release.yml` — the filename only, never a path |
| Environment | leave empty (these jobs bind no GitHub Environment) |
| Allowed actions | `npm publish` |

The repository is the mirror because the workflow that actually runs `npm
publish` is the mirror's exported copy of the file. Registering `vitruvian-core`
would look right and never match.

`pulumi-library` publishes **31** packages, so it needs 31 entries — one per
package under `pulumi/library/ts/packages/`.

## Verifying it worked

A successful publish logs an OIDC exchange rather than a token read, and
`npm view <pkg> dist-tags.latest` should equal the version in the repo. To check
the whole set at once:

```bash
bazel run //tools/npm-publish-audit:check
```

which compares every public package's repo version against the registry and
fails if any is behind.
