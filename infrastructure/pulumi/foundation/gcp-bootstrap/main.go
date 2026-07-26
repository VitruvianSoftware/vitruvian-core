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

// Mirrors: 0-bootstrap/main.tf in the TF foundation — the stage entrypoint
// that wires the per-concern pieces together. Each concern lives in its own
// file, matching upstream's file-per-concern layout:
//
//	config.go          — variables.tf   (stack config surface)
//	groups.go          — groups.tf      (optional Google Workspace groups)
//	projects.go        — main.tf        (bootstrap folder + seed/CI-CD projects)
//	sa.go              — sa.tf          (granular SAs + least-privilege IAM)
//	build_github.go    — build_github.tf.example (default builder: GitHub WIF)
//	outputs.go         — outputs.tf     (common stage outputs)
//	outputs_github.go  — outputs_github.tf.example (builder-specific outputs)
package main

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		// 1. Load Configuration (see config.go)
		cfg := loadConfig(ctx)

		// 1b. Optionally create Google Workspace groups (see groups.go).
		// Groups must exist before IAM bindings reference them.
		groupOpts, err := groupsProviderOptions(ctx, cfg)
		if err != nil {
			return err
		}
		groupResources, err := deployGroups(ctx, cfg, groupOpts...)
		if err != nil {
			return err
		}

		// 2. Create the Bootstrap Folder (see projects.go)
		bootstrapFolder, folderID, err := deployBootstrapFolder(ctx, cfg)
		if err != nil {
			return err
		}

		// 2b. Authorize project-metadata (label/name) UPDATES before any project is
		// created or updated. On a migration apply the seed + cicd label update needs
		// resourcemanager.projects.update, granted by the foundationProjectMetadataUpdater
		// custom org role bound to the bootstrap SA. That grant must be effective
		// (created AND IAM-propagated) before the update runs. When bootstrap_sa_email
		// is set we bind it via a config-derived STRING member so the grant chain does
		// NOT depend on the seed project that hosts the SA — breaking the
		// seed -> SA -> grant -> seed cycle — and return a propagation-wait gate the
		// projects are ordered behind. When unset (fresh org) this is a no-op and the
		// legacy in-deployIAM path applies (create-with-labels, no update).
		grant, err := authorizeProjectMetadataUpdates(ctx, cfg, groupResources)
		if err != nil {
			return err
		}

		// 3. Deploy the Seed Project (state storage and SA hosting)
		// Bucket IAM members are added later in deployIAM once SAs exist.
		seed, err := deploySeedProject(ctx, cfg, folderID, nil, grant)
		if err != nil {
			return err
		}

		// 4. Deploy the CI/CD Project (pipeline hosting)
		cicd, err := deployCICDProject(ctx, cfg, folderID, grant)
		if err != nil {
			return err
		}

		// 5. Deploy IAM: granular service accounts with least-privilege
		// bindings (see sa.go)
		sas, err := deployIAM(ctx, cfg, seed, cicd, groupResources, grant)
		if err != nil {
			return err
		}

		// 5b. Deploy CI/CD Build Infrastructure (GitHub Actions WIF by
		// default, see build_github.go)
		// Pulumi ESC federation: lets an agent session obtain GCP credentials with
		// no key anywhere, since the org forbids SA keys. Gated on pulumi_esc_org;
		// unset, this is a no-op and //tools/gcp-token's tailnet broker stays the
		// only path. See build_pulumi_esc.go.
		escOutputs, err := deployPulumiESCOIDC(ctx, cfg, cicd)
		if err != nil {
			return err
		}
		exportPulumiESCOutputs(ctx, cfg, escOutputs)

		buildOutputs, err := deployGitHubActionsBuild(ctx, cfg, seed, cicd, sas)
		if err != nil {
			return err
		}

		// 6. Exports — matching TF outputs.tf (see outputs.go)
		exportOutputs(ctx, cfg, bootstrapFolder, seed, cicd, sas, buildOutputs)

		// 7. Builder-specific outputs — mirrors upstream's per-builder
		// outputs_*.tf files (outputs_github.tf.example here; swap for
		// exportCloudBuildOutputs / exportGitLabOutputs /
		// exportTerraformCloudOutputs when switching builders).
		exportGitHubOutputs(ctx, cicd)

		return nil
	})
}
