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


# Deploying the relay

The relay runs on the homelab cluster, public at
`https://relay.vitruviansoftware.dev` once the new image is live (see
[Two modes](#two-modes-and-the-switch-between-them)); until then at
`https://relay.ipv1337.dev`.

- **Image:** `Dockerfile` here, built and pushed to
  `ghcr.io/vitruviansoftware/vitruvian-relay` by
  `.github/workflows/vitruvian-relay-image.yaml` on every push to `main` that
  touches the relay workspace or `packages/mcp-auth`. The run's
  summary prints the digest to pin.
- **Chart:** `chart/` (`vitruvian-relay`). It refuses to render without the
  image digest, the Zitadel ids and who may sign in. CI renders it in its new
  mode with `tools/ci/chart-render/vitruvian-relay.values.yaml` (the real client
  ids, a placeholder digest): `bazel run //tools/ci:chart_render`.
- **Devices and call history** live in Postgres: the CloudNativePG cluster
  `relay-db` in the `relay` namespace (3 instances, nightly backups to MinIO;
  manifests in `gitops/argocd/platform/relay/`). The relay takes its connection
  string from the `relay-db-app` secret and checks the server's certificate
  against `relay-db-ca`. It creates its own tables at start. The relay keeps no
  content: the tables hold names, sizes, times and outcomes, never arguments or
  results.
- **The old device file** (`/data/devices.json` on a 1 GiB `nfs` volume) is
  only for the old image (`persistence.enabled`). The new relay does not read
  it: people sign in and register again. When the digest PR turns the volume
  off, the claim stops being rendered and Argo CD leaves it (and its data) in
  place (`Prune=false`); delete it by hand later, once nothing needs the file.
- **Idle connections:** a `BackendTrafficPolicy` makes Envoy drop an idle
  upstream connection after 60 s, before the relay's own 75 s close.
  Cloudflare's tunnel talks to Envoy, not to the pod, so nothing else needs
  changing.

## Before Gemini can use this URL

Gemini's OAuth callback is tied to the server URL it was set up with. The new
relay URL gets a new callback, so add it to `geminiRedirectUris` in the
`zitadel-apps-relay` stack
([`infrastructure/pulumi/platform/zitadel-apps-relay`](../../../../../infrastructure/pulumi/platform/zitadel-apps-relay/README.md))
before connecting Gemini to it. Claude's callback is fixed and needs nothing.

## Two modes, and the switch between them

Argo CD deploys the chart and the values file from `main` the moment a PR merges,
but the new image only exists after that merge (the image workflow builds it
from `main`). So the chart can run either relay, chosen by values whose defaults
are the old one, and the move is two steps (expand, then switch):

| | Old relay (the defaults) | New relay (the digest PR) |
|---|---|---|
| `hostname` | `relay.ipv1337.dev` | `relay.vitruviansoftware.dev` |
| `database.enabled` | off: no `DATABASE_URL`, no path to `relay-db` | on |
| `persistence.enabled` | on: `/data` volume, read-write, `DATA_DIR` | off: no volume |
| `oidc.allowedSubjects` / `oidc.requiredRole` | the user list | the role (`relay-user`) |
| `oidc.dashboardClientId`, `mcpClientLabels` | empty: no dashboard, no dashboard paths in the HTTPRoute | set |

The cluster, its backups and the sealed secrets deploy in the first step either
way: they are additions the old relay never looks at.

Step two is a values-only PR (`gitops/argocd/platform/relay/values.yaml`): the
new image digest and the new-mode values, which is the file
`tools/ci/chart-render/vitruvian-relay.values.yaml` plus the digest and the node
affinity. It moves the hostname, so external-dns drops the `relay.ipv1337.dev`
record and the HTTPRoute stops serving that name in the same sync.

### App sign-in (Gemini with one URL), off until switched on

`appSignin.enabled` (default off) makes the relay an OAuth server for AI apps
that register themselves, so a person pastes one URL into Gemini and leaves the
client id and secret blank. It is wired in three places, all inert until the
switch is on, and turning it on is its own values PR
(`gitops/argocd/platform/relay/values.yaml`):

| What | Where |
|---|---|
| The Zitadel client the relay signs people in with | `relay-apps` in `zitadel-apps-relay` (`appsClientId` output). Created by CI on merge; the relay does not use it until the switch is on |
| The key the relay seals its sign-in state with | SealedSecret `relay-app-signin`, key `app-signin-key`, in `gitops/argocd/platform/sealed-secrets-manifests/` (not in this app's folder: the relay Argo project does not allow SealedSecret) |
| The chart | `appSignin.enabled`, `appSignin.secretName`, `appSignin.secretKey`, `oidc.appsClientId` |

With the switch on, the chart refuses to render unless `oidc.appsClientId` is set
**and** is also listed in `oidc.mcpClientIds` (the relay refuses to start
otherwise), the pod gets `APPS_CLIENT_ID` and `APP_SIGNIN_KEY`, and the HTTPRoute
also publishes `/oauth/`, `/mcp/app/` and `/.well-known/oauth-authorization-server`
(the protected-resource metadata for `/mcp/app/` is under the existing
`/.well-known/oauth-protected-resource` prefix). With it off, the render is
byte-for-byte what it was. The relay's dashboard then also shows the Gemini
address, and `vrelay login` prints it (the relay sends it back when a computer
registers, only when the feature is on).

The CI render values turn the switch on (with a placeholder client id) so the
templates and their refusals are tested; the live values do not copy that block
until the values PR.

#### Turning app sign-in on, in order

1. **Merge** the change that adds app sign-in. Nothing is live yet: the switch
   is off, so the relay behaves as before.
2. **Confirm the `relay-app-signin` Secret exists** in the `relay` namespace
   (the SealedSecret is applied by Argo CD, and the controller must have
   unsealed it). The pod will not start with the switch on if it is missing.
3. **Apply the Zitadel client** (`relay-apps`, in the `zitadel-apps-relay`
   stack). CI does this on merge; check the `appsClientId` output exists before
   going on.
4. **Open the values PR** (`gitops/argocd/platform/relay/values.yaml`): turn
   `appSignin.enabled` on, set `oidc.appsClientId`, add the same id to
   `oidc.mcpClientIds`, and add its label (below).

The label is the key under `mcpClientLabels`, and it must be a **new** one such
as `"Gemini (app sign-in)"`. The plain `Gemini` key is taken by the v2 client
(the one with Gemini's callbacks listed in Zitadel) until that client is
removed, and a label can name only one client id. The dashboard shows this label
next to the connection.

```yaml
mcpClientLabels:
  Claude: "400571151425734985"
  Gemini: "400571151492842651"          # v2 client, until it is removed
  "Gemini (app sign-in)": "<appsClientId>"
```

#### Cutting off access

There is no per-app revoke yet. An Allow gives that Gemini account a token for
every computer on the person's account, so to cut access off:

- **Remove the computer** in the dashboard. It takes effect on the next
  request, and the app's refresh stops working. Removing one computer does not
  cut off the person's others.
- **Remove the person's `relay-user` role** in Zitadel. Refresh stops, but an
  access token already issued keeps working until it expires: the role travels
  inside the token, so it is not looked up again on each call.

See "Known limits" in
[the design](../../../../../docs/superpowers/specs/2026-11-22-relay-app-sign-in-design.md).

### The new hostname

`relay.vitruviansoftware.dev` is published the way `storybook.`, `stats.` and
`mini-games-rooms.vitruviansoftware.dev` already are: the chart's `DNSEndpoint`
(`hostname`) makes a proxied CNAME to the Cloudflare Tunnel, external-dns
creates it (its `domainFilters` include `vitruviansoftware.dev`), and the tunnel
hands the request to the Gateway's plain HTTP listener, which routes by `Host`.
Cloudflare's edge terminates TLS, so there is no certificate in the cluster to
add. Nothing in a Pulumi or Cloudflare stack changes.

Once the old relay is gone, remove the old-mode values from the chart (the
`allowedSubjects` check, `persistence`, the `database.enabled` switch) and make
the new defaults the chart's.
