/*
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
*/

// Package upstash provisions Upstash Redis as code.
//
// Upstash has no native Pulumi provider, so this wraps the OFFICIAL
// `upstash/upstash` Terraform provider, bridged to a Go SDK with
// `pulumi package add terraform-provider` and vendored under ./sdk. Bridged
// providers are established practice in this repo — pulumiverse/pulumi-zitadel
// and pulumiverse/pulumi-time are both TF bridges — the only difference being
// that nobody publishes a Pulumi SDK for Upstash, so we generate it.
//
// The vendored SDK is RE-HOMED under this module's path rather than left at
// `github.com/pulumi/pulumi-terraform-provider/...`. `pulumi package add` wires
// that up with a `replace` directive, and replace directives do NOT propagate to
// consumers — a published library depending on one would fail to resolve for
// anyone who `go get`s it.
//
// What this component adds over calling the SDK directly:
//   - safe defaults for a CACHE (TLS on explicitly, eviction on) rather than the
//     provider's, so a future default-flip cannot silently downgrade a caller;
//   - the assembled connection URL as a SECRET output, so callers do not
//     hand-build `rediss://default:<pw>@<host>:<port>` and cannot accidentally
//     leak the password into a plan diff or CI log.
package upstash

import (
	"errors"
	"fmt"

	"github.com/VitruvianSoftware/pulumi-library/go/pkg/upstash/sdk/upstash"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// RedisArgs configures a single Upstash Redis database.
type RedisArgs struct {
	// Name is the database name as it appears in the Upstash console. Required.
	Name string
	// Region is the Upstash region, e.g. "us-east-1". Required — there is no
	// sensible default, and the wrong one silently adds cross-region latency to
	// every cache read.
	Region string
	// Eviction controls whether keys are evicted when the database is full.
	// Defaults to TRUE (cache semantics). Set false only for datastore use: a
	// full non-evicting database REJECTS writes, which takes the caller down,
	// whereas an evicting one merely degrades.
	Eviction *bool
	// AutoScale opts into Upstash's automatic plan upgrades on quota. Off by
	// default: it changes the bill without asking.
	AutoScale *bool
	// IPAllowlist restricts which CIDRs may connect. Empty means Upstash's
	// default (all IPs) — acceptable for a TLS+password endpoint reached from
	// serverless runtimes with no stable egress range, which is the common case.
	IPAllowlist []string
}

// Redis is a provisioned Upstash Redis database.
type Redis struct {
	// Database is the underlying resource, for callers needing a field this
	// component does not surface.
	Database *upstash.RedisDatabase
	// ConnectionURL is `rediss://default:<password>@<endpoint>:<port>`, marked
	// SECRET because it embeds the password.
	ConnectionURL pulumi.StringOutput
	// Endpoint is the hostname, non-secret and safe to log.
	Endpoint pulumi.StringOutput
}

// NewRedis provisions one Upstash Redis database.
func NewRedis(ctx *pulumi.Context, name string, args *RedisArgs, opts ...pulumi.ResourceOption) (*Redis, error) {
	if args == nil {
		return nil, errors.New("upstash.NewRedis: args are required")
	}
	if args.Name == "" {
		return nil, errors.New("upstash.NewRedis: Name is required")
	}
	if args.Region == "" {
		return nil, fmt.Errorf("upstash.NewRedis: Region is required for %q", args.Name)
	}

	eviction := true
	if args.Eviction != nil {
		eviction = *args.Eviction
	}
	autoScale := false
	if args.AutoScale != nil {
		autoScale = *args.AutoScale
	}

	dbArgs := &upstash.RedisDatabaseArgs{
		DatabaseName: pulumi.String(args.Name),
		Region:       pulumi.String(args.Region),
		Eviction:     pulumi.Bool(eviction),
		AutoScale:    pulumi.Bool(autoScale),
		// Explicit rather than inherited: TLS is Upstash's current default and
		// cannot be disabled on new databases, but pinning it here means a
		// provider-side default change can never quietly downgrade a caller.
		Tls: pulumi.Bool(true),
	}
	if len(args.IPAllowlist) > 0 {
		dbArgs.IpAllowlists = pulumi.ToStringArray(args.IPAllowlist)
	}

	db, err := upstash.NewRedisDatabase(ctx, name, dbArgs, opts...)
	if err != nil {
		return nil, fmt.Errorf("upstash.NewRedis %q: %w", args.Name, err)
	}

	// rediss:// (not redis://) — TLS is enabled above, and a plaintext scheme
	// against a TLS-only endpoint fails at connect time rather than falling back.
	url := pulumi.All(db.Endpoint, db.Password, db.Port).ApplyT(
		func(v []interface{}) string {
			return fmt.Sprintf("rediss://default:%s@%s:%v", v[1], v[0], v[2])
		},
	).(pulumi.StringOutput)

	return &Redis{
		Database:      db,
		ConnectionURL: pulumi.ToSecret(url).(pulumi.StringOutput),
		Endpoint:      db.Endpoint,
	}, nil
}
