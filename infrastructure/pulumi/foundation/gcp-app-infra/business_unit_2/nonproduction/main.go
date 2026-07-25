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
// 5-app-infra/business_unit_2/nonproduction. This leaf pins the environment
// identity (development/d) and reads/re-exports the stage-4 facts an app needs.
//
// File layout mirrors the upstream leaf: main.go (orchestration, upstream
// main.tf), config.go (variables.tf), remote.go (remote.tf), outputs.go
// (outputs.tf). Note 5-app-infra has NO `shared` leaf, unlike 4-projects.
//
// WHAT THIS LEAF OWNS, AND WHY
// (docs/engineering/core-vs-application-infrastructure.md):
//   - SCAFFOLDING ONLY. It creates ZERO GCP resources. It CONSUMES the stage-4
//     gcp-projects facts (host project id/number, region, per-app deploy SA) via
//     StackReference and re-EXPORTS them (outputs.go) as the contract each app's
//     own infra/app stack reads.
//
// It deliberately does NOT own the container WORKLOAD (the Cloud Run service).
// The workload is image-coupled, so it lives in the app's own Pulumi stack
// (<app>/infra/app), deployed by the app's pipeline WITH the image digest that
// pipeline builds — never in this image-less foundation stage. It also does NOT
// own the platform-issued deploy identity (minted one stage up in
// gcp-projects/modules/app_deploy_identity); this leaf only re-exports it, which
// is what lets this stage be deployed BY that identity without a per-app
// reviewer gate.
package main

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Environment pinned by this leaf project — upstream
// 5-app-infra/business_unit_2/nonproduction hardcodes env in its main.tf; the
// leaf dir is the pin, not per-stack config.
const (
	pinnedEnv     = "nonproduction"
	pinnedEnvCode = "n"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := loadConfig(ctx)

		// Cross-stage StackReferences (remote.go) — the env's app-hosting
		// project from stage 4 and the shared WIF pool from stage 0.
		refs, err := loadStackReferences(ctx, cfg)
		if err != nil {
			return err
		}

		// Scaffolding contract only: re-export the stage-4 facts (project
		// id/number, region, per-app deploy SA) that each app's own infra/app
		// stack consumes. No workload is created here.
		exportOutputs(ctx, cfg, refs, refs.DeployServiceAccounts)
		return nil
	})
}
