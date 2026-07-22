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

// Foundation stage 5 (app-infra) — thin business-unit leaf for the development
// environment, mirroring upstream terraform-example-foundation
// 5-app-infra/business_unit_1/development. This leaf pins the environment
// identity (development/d) and calls the shared modules/ for the application
// infrastructure that belongs to the platform.
//
// File layout mirrors the upstream leaf: main.go (orchestration, upstream
// main.tf), config.go (variables.tf), remote.go (remote.tf), outputs.go
// (outputs.tf). Note 5-app-infra has NO `shared` leaf, unlike 4-projects.
//
// WHAT THIS LEAF OWNS, AND WHY
// (docs/engineering/core-vs-application-infrastructure.md):
//   - Application WORKLOADS built from the stage's archetype catalog.
//
// It deliberately does NOT own the platform-issued deploy identity. That is
// minted one stage up, in gcp-projects/modules/app_deploy_identity, mirroring
// upstream's seeding of app-infra pipeline SAs in 4-projects. The separation
// is what lets this stage be deployed BY that identity without a reviewer gate
// on every routine app deploy: the identity cannot edit its own grants,
// because its grants live in a stage it does not deploy. This leaf CONSUMES
// the identity by StackReference and re-exports it.
//
// SERVERLESS WORKLOADS are wired through modules/serverless_space, but each app
// is gated on <app>_workload_enabled and every app currently ships FALSE. A
// Pulumi stack cannot take ownership of a live resource by declaring it, so the
// cutover per env is: `pulumi import` the running service into this stack, flip
// this flag, then state-delete it from the app stack. Until then the app's own
// stack keeps serving. Runbook:
// docs/engineering/core-vs-application-infrastructure.md §7.
package main

import (
	"os"
	"strings"

	"foundation-app-infra/modules/serverless_space"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Per-invocation deploy inputs come from the environment, never committed
// config: the image digest is produced by the build-once job and the
// promote/stable-revision pair drives blue-green. Mirrors how the app stack
// reads them today (<APP_PREFIX>_IMAGE_DIGEST etc.), so the deploy workflow
// keeps the same contract across the cutover.
func appEnv(app, suffix string) string {
	return os.Getenv(strings.ToUpper(strings.ReplaceAll(app, "-", "_")) + "_" + suffix)
}

func imageDigest(app string) string    { return appEnv(app, "IMAGE_DIGEST") }
func stableRevision(app string) string { return appEnv(app, "STABLE_REVISION") }
func promote(app string) bool          { return appEnv(app, "PROMOTE") == "true" }

// revisionSuffix derives a stable, referenceable revision name fragment from
// the digest — a digest is not itself a legal revision name.
func revisionSuffix(app string) string {
	d := imageDigest(app)
	if i := strings.LastIndex(d, "@sha256:"); i >= 0 && len(d) >= i+16 {
		return d[i+8 : i+16]
	}
	return ""
}

// Environment pinned by this leaf project — upstream
// 5-app-infra/business_unit_1/development hardcodes env in its main.tf; the
// leaf dir is the pin, not per-stack config.
const (
	pinnedEnv     = "development"
	pinnedEnvCode = "d"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := loadConfig(ctx)

		// 1. Cross-stage StackReferences (remote.go) — the env's app-hosting
		// project from stage 4 and the shared WIF pool from stage 0.
		refs, err := loadStackReferences(ctx, cfg)
		if err != nil {
			return err
		}

		// Deploy identities are consumed, not created (see the package note).
		deploySAs := refs.DeployServiceAccounts

		// Serverless workloads, per app, gated on the cutover switch.
		serviceURLs := map[string]pulumi.StringOutput{}
		serviceNames := map[string]pulumi.StringOutput{}
		for _, app := range cfg.Apps {
			if !app.WorkloadEnabled {
				continue
			}
			res, err := serverless_space.DeployServerlessSpace(ctx, app.Name, &serverless_space.ServerlessSpaceArgs{
				Env:                        cfg.Env,
				BusinessUnit:               cfg.BusinessCode,
				ProjectID:                  refs.OSSFloatingProjectID,
				Region:                     cfg.Region,
				ServiceName:                app.ServiceName,
				ImageDigest:                pulumi.String(imageDigest(app.Name)),
				RuntimeServiceAccountEmail: pulumi.String(app.RuntimeServiceAccount),
				SecretPrefix:               app.SecretPrefix,
				EnvVars: map[string]string{
					"NODE_ENV": "production",
				},
				PublicInvoker:  app.PublicInvoker,
				MaxInstances:   app.MaxInstances,
				RevisionSuffix: revisionSuffix(app.Name),
				StableRevision: stableRevision(app.Name),
				Promote:        promote(app.Name),
			})
			if err != nil {
				return err
			}
			serviceURLs[app.Name] = res.ServiceUri
			serviceNames[app.Name] = res.ServiceName
		}
		for app, u := range serviceURLs {
			ctx.Export(app+"_service_uri", u)
		}
		for app, n := range serviceNames {
			// The app stack's DomainMapping binds by the run service's SHORT
			// NAME, so it must read this once the workload lives here.
			ctx.Export(app+"_service_name", n)
		}

		exportOutputs(ctx, cfg, refs, deploySAs)
		return nil
	})
}
