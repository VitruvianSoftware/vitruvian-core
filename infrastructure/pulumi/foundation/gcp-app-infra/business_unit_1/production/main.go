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
// NOT YET INSTANTIATED: modules/serverless_space (the Cloud Run archetype) is
// ported and compiled but no app is wired through it here yet.
// oauth-user-inspector's Cloud Run service is still deployed by
// oauth-user-inspector/infra/app; moving it onto the archetype adopts a live,
// traffic-serving service and is deliberately a separate change so it can be
// reverted on its own.
package main

import "github.com/pulumi/pulumi/sdk/v3/go/pulumi"

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

		// Deploy identities are consumed, not created (see the package note).
		deploySAs := refs.DeployServiceAccounts

		exportOutputs(ctx, cfg, refs, deploySAs)
		return nil
	})
}
