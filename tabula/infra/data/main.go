// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// Package main is tabula's stateful tier: the Neon Postgres projects and the
// Upstash Redis the app runs on, plus the Secret Manager versions that carry
// their connection strings into each environment.
//
// SINGLE STACK, NOT PER-ENV — deliberately, and unlike tabula/infra/app.
// Neon projects and Upstash databases are not GCP resources: they live in one
// Neon organization and one Upstash account, so splitting them across three
// per-env stacks would give three stacks partial views of the same external
// account and no single place that says what tabula's data tier IS. This
// mirrors tabula/infra/build, the other cross-environment singleton.
//
// The GCP side is still per-env: each environment's connection string is
// written into THAT environment's own project, under the TABULA_ prefix the
// runtime reads (tabula/api/src/lib/secrets.ts).
//
// Deploy: CI only (.github/workflows/tabula-data-stack.yaml). Credentials for
// both providers come from the infra-pipeline project's Secret Manager, seeded
// out of band with `bazel run //tools/gcp-secrets:seed -- tabula/infra/build`.
package main

import (
	"fmt"

	"github.com/VitruvianSoftware/pulumi-library/go/pkg/neon"
	"github.com/VitruvianSoftware/pulumi-library/go/pkg/upstash"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/secretmanager"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// env is one tabula environment and the GCP project its secrets live in.
type env struct {
	// name is the Pulumi/GitHub environment name, and the suffix of the Neon
	// project so the Neon console is readable at a glance.
	name string
	// gcpProject is the env's oss-floating project, where the connection strings
	// are written as TABULA_-prefixed secrets.
	gcpProject string
}

// secretVersion writes value into <project>/<TABULA_ + id> as a new version.
//
// The CONTAINER is not declared here: it is created by the identity stack,
// which also owns the per-secret IAM that lets the deploy and runtime SAs read
// it. This stack only supplies values, so a change here can never widen access.
func secretVersion(ctx *pulumi.Context, resName, project, id string, value pulumi.StringOutput) error {
	_, err := secretmanager.NewSecretVersion(ctx, resName, &secretmanager.SecretVersionArgs{
		// The provider accepts a fully-qualified secret name here, which avoids a
		// StackReference just to learn the container's id.
		Secret:     pulumi.String(fmt.Sprintf("projects/%s/secrets/TABULA_%s", project, id)),
		SecretData: value,
	})
	return err
}

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "tabula-data")

		neonOrgID := cfg.Require("neonOrgId")
		// Neon and Upstash name regions differently ("aws-us-east-1" vs
		// "us-east-1"); both default to us-east-1 to sit near the us-central1
		// Cloud Run services without paying for multi-region.
		neonRegion := cfg.Get("neonRegionId")
		if neonRegion == "" {
			neonRegion = "aws-us-east-1"
		}
		upstashRegion := cfg.Get("upstashRegion")
		if upstashRegion == "" {
			upstashRegion = "us-east-1"
		}

		envs := []env{
			{name: "development", gcpProject: cfg.Require("developmentProject")},
			{name: "nonproduction", gcpProject: cfg.Require("nonproductionProject")},
			{name: "production", gcpProject: cfg.Require("productionProject")},
		}

		// --- Postgres: one Neon project per environment -----------------------
		//
		// A Neon PROJECT (not a branch) per env is the isolation boundary that
		// matters: branches of one project share its compute and connection
		// limits, so a dev load test would contend with production.
		for _, e := range envs {
			p, err := neon.NewProject(ctx, "neon-"+e.name, &neon.ProjectArgs{
				Name:     "tabula-" + e.name,
				RegionID: neonRegion,
				OrgID:    neonOrgID,
				// Defaults from the module: database "main", role "app", pinned
				// Postgres major, and the POOLED connection string — Cloud Run
				// scales to many short-lived instances and Postgres has a hard
				// max_connections.
			})
			if err != nil {
				return err
			}
			if err := secretVersion(ctx, "db-url-"+e.name, e.gcpProject, "DATABASE_URL", p.ConnectionString); err != nil {
				return err
			}
			ctx.Export("neon_project_"+e.name, p.ID)
		}

		// --- Cache: ONE Upstash Redis shared by all three environments ---------
		//
		// Deliberate, not an oversight. The Upstash account's free tier caps at a
		// single database, and tabula is pre-launch, so the isolation this gives
		// up is accepted for now. The cost is real and worth stating: the three
		// environments share a keyspace, so a dev flush or a key collision
		// reaches production. Sessions and cache both live here.
		//
		// To split later: give each env its own upstash.NewRedis with
		// `tabula-<env>` and point that env's secret at it — the loop above is
		// the shape to copy. That needs a paid Upstash plan.
		cache, err := upstash.NewRedis(ctx, "redis-shared", &upstash.RedisArgs{
			Name:   "tabula-shared",
			Region: upstashRegion,
			// Eviction defaults ON in the module: a full non-evicting Redis
			// REJECTS writes, which would take every environment down at once
			// given they share this instance.
		})
		if err != nil {
			return err
		}
		for _, e := range envs {
			if err := secretVersion(ctx, "redis-url-"+e.name, e.gcpProject, "UPSTASH_REDIS_URL", cache.ConnectionURL); err != nil {
				return err
			}
		}
		ctx.Export("upstash_endpoint", cache.Endpoint)

		return nil
	})
}
