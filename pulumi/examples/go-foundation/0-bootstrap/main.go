/*
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

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

		// 3. Deploy the Seed Project (state storage and SA hosting)
		// Bucket IAM members are added later in deployIAM once SAs exist.
		seed, err := deploySeedProject(ctx, cfg, folderID, nil)
		if err != nil {
			return err
		}

		// 4. Deploy the CI/CD Project (pipeline hosting)
		cicd, err := deployCICDProject(ctx, cfg, folderID)
		if err != nil {
			return err
		}

		// 5. Deploy IAM: granular service accounts with least-privilege
		// bindings (see sa.go)
		sas, err := deployIAM(ctx, cfg, seed, cicd, groupResources)
		if err != nil {
			return err
		}

		// 5b. Deploy CI/CD Build Infrastructure (GitHub Actions WIF by
		// default, see build_github.go)
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
