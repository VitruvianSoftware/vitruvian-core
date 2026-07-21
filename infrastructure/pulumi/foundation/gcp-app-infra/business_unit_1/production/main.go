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

// Foundation stage 5 (app-infra) — thin business-unit leaf for the production
// environment, mirroring upstream terraform-example-foundation
// 5-app-infra/business_unit_1/production. This leaf pins the environment
// identity (development/d) and calls the shared modules/ for the application
// infrastructure that belongs to the platform.
//
// File layout mirrors the upstream leaf: main.go (orchestration, upstream
// main.tf), config.go (variables.tf), remote.go (remote.tf), outputs.go
// (outputs.tf). Note 5-app-infra has NO `shared` leaf, unlike 4-projects.
//
// WHAT THIS LEAF OWNS, AND WHY
// (docs/engineering/core-vs-application-infrastructure.md):
//   - The platform-ISSUED deploy identity per app per env, and the grants that
//     reach outside the application. An app may create its own service
//     accounts, but only the foundation may grant an identity power over a
//     project the app does not own.
//
// NOT YET INSTANTIATED: modules/serverless_space (the Cloud Run archetype) is
// ported and compiled but no app is wired through it here yet.
// oauth-user-inspector's Cloud Run service is still deployed by
// oauth-user-inspector/infra/app; moving it onto the archetype adopts a live,
// traffic-serving service and is deliberately a separate change so it can be
// reverted on its own.
package main

import (
	"foundation-app-infra/modules/app_deploy_identity"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Environment pinned by this leaf project — upstream
// 5-app-infra/business_unit_1/production hardcodes env in its main.tf; the
// leaf dir is the pin, not per-stack config.
const (
	pinnedEnv     = "production"
	pinnedEnvCode = "p"
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

		// 2. Platform-issued deploy identity per application.
		deploySAs := map[string]pulumi.StringOutput{}
		for _, app := range cfg.Apps {
			res, err := app_deploy_identity.Deploy(ctx, app.Name, &app_deploy_identity.Args{
				App:                  app.Name,
				Env:                  cfg.Env,
				ProjectID:            refs.OSSFloatingProjectID,
				DeployAccountID:      app.DeployAccountID,
				DeployRoles:          app.DeployRoles,
				WorkloadIdentityPool: refs.WorkloadIdentityPool,
				GitHubEnvironment:    app.GitHubEnvironment(cfg.Env),
			})
			if err != nil {
				return err
			}
			deploySAs[app.Name] = res.DeployServiceAccountEmail
		}

		exportOutputs(ctx, cfg, refs, deploySAs)
		return nil
	})
}
