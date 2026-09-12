# upstash

Provision **Upstash Redis** as code.

```go
import "github.com/VitruvianSoftware/pulumi-library/go/pkg/upstash"

cache, err := upstash.NewRedis(ctx, "cache", &upstash.RedisArgs{
    Name:   "tabula-shared",
    Region: "us-east-1",
})
// cache.ConnectionURL is a SECRET output: rediss://default:<pw>@<host>:<port>
```

## Why a bridged provider

Upstash has no native Pulumi provider, so this wraps the **official**
`upstash/upstash` Terraform provider, bridged with
`pulumi package add terraform-provider` and vendored under `./sdk`.

Bridged providers are established practice here — `pulumiverse/pulumi-zitadel`
and `pulumiverse/pulumi-time` are both TF bridges. The only difference is that
nobody publishes a Pulumi SDK for Upstash, so we generate it.

The vendored SDK is **re-homed under this module's path** and kept as a *package*
of this module rather than a nested module. `pulumi package add` normally wires it
up with a `replace` directive, and replace directives do **not** propagate to
consumers — a published library depending on one fails to resolve for anyone who
`go get`s it.

## What the component adds

- **Cache-safe defaults.** Eviction **on** by default: a full non-evicting Redis
  *rejects writes* and takes the caller down, whereas an evicting one degrades.
  Set `Eviction: &false` for datastore use.
- **TLS pinned explicitly** rather than inherited. It is Upstash's current default
  and can't be disabled on new databases, but pinning it means a provider-side
  default change can never quietly downgrade a caller to plaintext.
- **The connection URL assembled for you, as a secret output.** Callers don't
  hand-build `rediss://default:<pw>@<host>:<port>`, and the password can't leak
  into a plan diff or CI log.

## Credentials

The provider reads `UPSTASH_EMAIL` and `UPSTASH_API_KEY`. Store them in Secret
Manager and seed the values with
[`//tools/gcp-secrets`](../../../../tools/gcp-secrets) — never inline.

## Regenerating the SDK

```sh
pulumi package add terraform-provider upstash/upstash
```
then re-home the module path from `github.com/pulumi/pulumi-terraform-provider/...`
to `github.com/VitruvianSoftware/pulumi-library/go/pkg/upstash/sdk` and delete the
generated `sdk/go.mod`. Treat a provider bump as a reviewed change.
