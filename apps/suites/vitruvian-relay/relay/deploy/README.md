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
