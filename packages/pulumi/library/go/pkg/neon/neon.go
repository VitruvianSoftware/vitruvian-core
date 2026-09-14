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

// Package neon provisions Neon serverless Postgres as code.
//
// ⚠️ Neon ships NO official Terraform or Pulumi provider. This wraps the
// community `kislerdm/neon` provider, bridged with
// `pulumi package add terraform-provider` and vendored under ./sdk. For a
// production database that is a real supply-chain consideration: the SDK is
// vendored (so a provider disappearing upstream cannot break a build) and the
// version is pinned, and a provider bump should be a reviewed change rather
// than an automerged one.
//
// Bridged providers are established practice in this repo —
// pulumiverse/pulumi-zitadel and pulumiverse/pulumi-time are both TF bridges.
//
// The vendored SDK is RE-HOMED under this module's path and kept as a PACKAGE of
// this module rather than a nested module: `pulumi package add` normally wires it
// up with a `replace` directive, and replace directives do NOT propagate to
// consumers, so a published library depending on one fails to resolve for anyone
// who `go get`s it.
package neon

import (
	"errors"
	"fmt"

	"github.com/VitruvianSoftware/pulumi-library/go/pkg/neon/sdk/neon"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// DefaultPgVersion is the Postgres major used when a caller does not pin one.
// Pinned deliberately: letting the provider pick means two environments created
// months apart silently run different majors.
const DefaultPgVersion = 17

// ProjectArgs configures one Neon project (a project is the isolation boundary —
// its own compute, storage and connection limits).
type ProjectArgs struct {
	// Name is the project name in the Neon console. Required.
	Name string
	// RegionID is e.g. "aws-us-east-1". Required — the wrong region adds
	// cross-region latency to every query, and it cannot be changed later
	// without recreating the project.
	RegionID string
	// OrgID homes the project in an organization rather than a personal account.
	// Strongly recommended: a project created outside an org is owned by an
	// individual, which is the thing app infrastructure should never depend on.
	OrgID string
	// DatabaseName is the initial database. Defaults to "main".
	DatabaseName string
	// RoleName is the owner role. Defaults to "app".
	RoleName string
	// PgVersion pins the Postgres major. Defaults to DefaultPgVersion.
	PgVersion *int
	// HistoryRetentionSeconds bounds point-in-time-restore history. Neon's own
	// default is 24h; left nil, that applies.
	HistoryRetentionSeconds *float64
	// Pooled selects which connection string ConnectionString returns.
	// Defaults to TRUE — see ConnectionString.
	Pooled *bool
}

// Project is a provisioned Neon project.
type Project struct {
	// Project is the underlying resource, for fields this component does not surface.
	Project *neon.Project
	// ConnectionString is the URI the app should use, marked SECRET because it
	// embeds credentials.
	//
	// Defaults to the POOLED endpoint. Serverless runtimes (Cloud Run) scale to
	// many short-lived instances, each opening its own connections; Postgres
	// enforces a hard max_connections, so a direct endpoint runs out under
	// exactly the traffic that scaling is supposed to absorb. The pooler is the
	// correct default for this repo's deployment model — set Pooled=false only
	// for a workload needing session-level features the pooler cannot proxy
	// (LISTEN/NOTIFY, session-scoped advisory locks, some prepared statements).
	ConnectionString pulumi.StringOutput
	// ID is the Neon project id, non-secret and safe to log or export.
	ID pulumi.StringOutput
}

// NewProject provisions one Neon project with its initial database and role.
func NewProject(ctx *pulumi.Context, name string, args *ProjectArgs, opts ...pulumi.ResourceOption) (*Project, error) {
	if args == nil {
		return nil, errors.New("neon.NewProject: args are required")
	}
	if args.Name == "" {
		return nil, errors.New("neon.NewProject: Name is required")
	}
	if args.RegionID == "" {
		return nil, fmt.Errorf("neon.NewProject: RegionID is required for %q", args.Name)
	}

	dbName := args.DatabaseName
	if dbName == "" {
		dbName = "main"
	}
	roleName := args.RoleName
	if roleName == "" {
		roleName = "app"
	}
	pgVersion := DefaultPgVersion
	if args.PgVersion != nil {
		pgVersion = *args.PgVersion
	}
	pooled := true
	if args.Pooled != nil {
		pooled = *args.Pooled
	}

	pArgs := &neon.ProjectArgs{
		Name:      pulumi.String(args.Name),
		RegionId:  pulumi.String(args.RegionID),
		PgVersion: pulumi.Float64(float64(pgVersion)),
		Branch: &neon.ProjectBranchArgs{
			DatabaseName: pulumi.String(dbName),
			RoleName:     pulumi.String(roleName),
		},
	}
	if args.OrgID != "" {
		pArgs.OrgId = pulumi.String(args.OrgID)
	}
	if args.HistoryRetentionSeconds != nil {
		pArgs.HistoryRetentionSeconds = pulumi.Float64(*args.HistoryRetentionSeconds)
	}

	p, err := neon.NewProject(ctx, name, pArgs, opts...)
	if err != nil {
		return nil, fmt.Errorf("neon.NewProject %q: %w", args.Name, err)
	}

	conn := p.ConnectionUriPooler
	if !pooled {
		conn = p.ConnectionUri
	}

	return &Project{
		Project:          p,
		ConnectionString: pulumi.ToSecret(conn).(pulumi.StringOutput),
		ID:               p.ID().ToStringOutput(),
	}, nil
}
