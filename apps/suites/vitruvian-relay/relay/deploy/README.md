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

The relay runs on the homelab cluster at `https://relay.ipv1337.dev`.

- **Image:** `Dockerfile` here, built and pushed to
  `ghcr.io/vitruviansoftware/vitruvian-relay` by
  `.github/workflows/vitruvian-relay-image.yaml` on every push to `main` that
  touches the relay workspace or `packages/mcp-auth`. The run's
  summary prints the digest to pin.
- **Chart:** `chart/` (`vitruvian-relay`). It refuses to render without the
  image digest and the Zitadel ids. CI renders it with
  `tools/ci/chart-render/vitruvian-relay.values.yaml` (placeholders only):
  `bazel run //tools/ci:chart_render`.
- **Device records** live on a 1 GiB `nfs` volume at `/data`. The pod runs as
  UID 10001 with `fsGroup: 10001` so it can write there.
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
