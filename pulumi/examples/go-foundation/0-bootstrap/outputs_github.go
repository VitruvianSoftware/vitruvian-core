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

/* ----------------------------------------
   Specific to github_bootstrap
  ---------------------------------------- */
// Mirrors: 0-bootstrap/outputs_github.tf.example in the TF foundation.
//
// NOTE on the suffix: upstream ships this file as `.example` because its
// default builder is Cloud Build; our port defaults to GitHub Actions, so the
// suffix is inverted here (this file is live, outputs_cb.go.example is the
// example) — matching the build_cloud_build.go.example/build_github_actions.go
// pattern.

package main

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// exportGitHubOutputs exports the GitHub-Actions-builder-specific outputs.
func exportGitHubOutputs(ctx *pulumi.Context, cicd *CICDProject) {
	// Project where the CI/CD infrastructure for GitHub Actions resides.
	ctx.Export("cicd_project_id", cicd.ProjectID)
}
