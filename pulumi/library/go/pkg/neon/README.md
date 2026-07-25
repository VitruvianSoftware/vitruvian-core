# neon

Provision **Neon serverless Postgres** as code.

```go
import "github.com/VitruvianSoftware/pulumi-library/go/pkg/neon"

db, err := neon.NewProject(ctx, "db", &neon.ProjectArgs{
    Name:     "tabula-development",
    RegionID: "aws-us-east-1",
    OrgID:    "org-...",
})
// db.ConnectionString is a SECRET output, POOLED by default
```

## ⚠️ Provider caveat — read this

**Neon ships no official Terraform or Pulumi provider.** This wraps the
community `kislerdm/neon` provider, bridged with
`pulumi package add terraform-provider` and vendored under `./sdk`.

For a production database that is a genuine supply-chain consideration. The
mitigations: the SDK is **vendored** (an upstream disappearance cannot break a
build), the version is **pinned**, and a provider bump should be a **reviewed**
change — not an automerged dependabot bump.

Bridged providers are established practice here — `pulumiverse/pulumi-zitadel`
and `pulumiverse/pulumi-time` are both TF bridges.

The vendored SDK is **re-homed** under this module's path and kept as a *package*
of this module, because `pulumi package add`'s `replace` directive does not
propagate to consumers.

## Defaults this component chooses

- **Pooled connection string.** Serverless runtimes scale to many short-lived
  instances, each opening connections, while Postgres enforces a hard
  `max_connections` — a direct endpoint runs out under exactly the traffic that
  scaling is meant to absorb. Set `Pooled: &false` only for session-level
  features the pooler can't proxy (`LISTEN`/`NOTIFY`, session advisory locks).
- **Pinned Postgres major** (`DefaultPgVersion`). Letting the provider pick means
  two environments created months apart silently run different majors.
- **`OrgID` strongly recommended.** A project created outside an organization is
  owned by an individual — the exact dependency this foundation exists to remove.
- **Secret connection string**, so credentials can't reach a plan diff or CI log.

## Credentials

The provider reads `NEON_API_KEY`. Store it in Secret Manager and seed the value
with [`//tools/gcp-secrets`](../../../../tools/gcp-secrets) — never inline.
