# Domain zone conventions

Which DNS zone an application lives on, and why. Two zones are in use and they
are **not** interchangeable — picking the wrong one is a copy-paste error that
survives review, because the resulting hostname looks perfectly normal.

| zone | Cloudflare zone id | holds |
| --- | --- | --- |
| `ipv1337.dev` | `a346c14c429c7356c0e4e3a9b623a104` | open-source applications, and all lab/platform infrastructure |
| `vitruviansoftware.dev` | `fa827eb1be98b4f6059cf34f90c64774` | commercial and paid-tier applications |

## Choosing a zone

**`ipv1337.dev` — open source, and everything that isn't an application.**

Use it when the app is fully open source with no paid tier, and for every piece
of platform or lab infrastructure regardless of what it serves:

- OSS apps — `oauth-inspector.ipv1337.dev`
- the dev-local cluster and its services — `k8s-api.lab.ipv1337.dev`,
  `argocd.lab.ipv1337.dev`, `grafana.lab.ipv1337.dev`
- shared identity — `auth.ipv1337.dev` (Zitadel)
- per-node and per-developer records — `node.ipv1337.dev`, `james.ipv1337.dev`

**`vitruviansoftware.dev` — commercial, or anything with a paid tier.**

Use it when the app is a product: closed source, or open-core with a paid tier,
or anything a customer would be billed for.

- `tabula-api.vitruviansoftware.dev` — partially open source, paid tier planned

The distinction is **commercial intent, not repository visibility.** An app can
live in a public repo and still belong on `vitruviansoftware.dev` if it has (or
will have) paying users. Tabula is exactly that case.

> ⚠️ `vitruviansoftware.dev` is **also the GCP organization's identity domain** —
> Cloud Identity accounts (`james@vitruviansoftware.dev`), the org's Google
> groups (`gcp-organization-admins@vitruviansoftware.dev`), and Workspace all
> hang off it. Adding application hostnames to that zone is fine and intended,
> but it means the zone carries both identity and product records: be careful
> with apex records and anything touching MX, SPF or DKIM, and never remove a
> TXT record you did not add.

## Per-environment hostnames

Every environment gets its own hostname on the app's chosen zone. Production is
the bare name; the lower environments are subdomains:

| environment | pattern | example |
| --- | --- | --- |
| development | `<app>.dev.<zone>` | `tabula-api.dev.vitruviansoftware.dev` |
| nonproduction | `<app>.staging.<zone>` | `tabula-api.staging.vitruviansoftware.dev` |
| production | `<app>.<zone>` | `tabula-api.vitruviansoftware.dev` |

Note that **nonproduction maps to `staging`** in DNS. The environment is called
`nonproduction` everywhere else (GCP project, GitHub environment, Pulumi stack);
only the hostname says `staging`.

Each hostname needs its own entry in every external allow-list the app depends
on — OAuth redirect URIs, API-key origin allow-lists, webhook URLs. A per-env
public URL means a per-env allow-list entry; that inventory is the bulk of the
work in onboarding an app, not the deploy.

## How it is wired

Both zones are Cloudflare-managed. For a Cloud Run app the per-env stack
(`<app>/infra/app`) creates two things:

1. a **grey-cloud** (`proxied: false`) CNAME to `ghs.googlehosted.com`, and
2. a Cloud Run **DomainMapping**, which provisions the certificate.

Grey-cloud is required: an orange-cloud (proxied) record puts Cloudflare in
front of Google's certificate provisioning and the mapping never goes routable.

Three config keys drive it, all in the app's `Pulumi.<env>.yaml`:

```yaml
  tabula-app:cloudflareZone: vitruviansoftware.dev
  tabula-app:cloudflareZoneId: fa827eb1be98b4f6059cf34f90c64774
  tabula-app:customDomain: tabula-api.dev.vitruviansoftware.dev
```

`cloudflareZoneId` is **pinned** rather than looked up so that a token-less PR
preview resolves the same id as the real deploy — without it the preview shows a
phantom `~zoneId` replace on every run. A zone id is not a secret; it appears in
the Cloudflare dashboard URL and in every preview diff.

### Domain ownership

Creating a DomainMapping requires the **deploying principal** to be a verified
owner of the domain in Google's Site Verification service, and ownership there is
**per-caller** — no service account can verify on another's behalf. Each
environment's deploy SA self-verifies its zone via DNS-TXT before its own
`pulumi up` (`tools/ci/ensure-site-verification.sh`).

The steady state is therefore **one `google-site-verification` TXT per env deploy
SA** on the zone apex, alongside any pre-existing one. For a three-environment
app on a zone that already had an owner, that is four TXT records. Never delete
one: Google re-checks DNS periodically, so removing a token revokes that
principal's ownership and the next deploy fails.

## Guardrails

Two automated checks enforce parts of this, both added after the failures they
describe actually happened:

- **`customDomain` must live under its `cloudflareZone`** (`tools/conformance/check.sh`).
  Both the CNAME and the ownership TXT are written into the zone named by
  `cloudflareZone`; if that is not the registrable parent of `customDomain`, both
  land on the *wrong* zone while DNS looks superficially fine, and the
  DomainMapping sits at `Caller is not authorized to administer the domain`. A
  config copied from an app on the other zone carries the source app's zone —
  which is precisely the copy-paste this check catches.
- **A `customDomain` with no `cloudflareZone` is a hard error**
  (`tools/ci/ensure-site-verification.sh`). It used to default to `ipv1337.dev`,
  which for a `vitruviansoftware.dev` app placed the verification TXT on the
  wrong domain entirely.

## Adding a new app

1. Decide the zone from **commercial intent**, per the rule above.
2. Pick the three hostnames using the per-environment pattern.
3. Set `cloudflareZone`, `cloudflareZoneId` and `customDomain` in each
   `Pulumi.<env>.yaml`. Conformance will reject a mismatched pair.
4. Register each hostname in every external allow-list the app uses.
5. If the app ships a client with a **compiled-in** API URL — a browser
   extension, a mobile app — stand the custom domain up and repoint the client
   **before** cutover. Decommissioning tabula's old service while its extension
   still had the `run.app` URL baked into `host_permissions` took that extension
   offline.

See also: [`docs/oss-app-onboarding-checklist.md`](../guides/oss-app-onboarding-checklist.md).
