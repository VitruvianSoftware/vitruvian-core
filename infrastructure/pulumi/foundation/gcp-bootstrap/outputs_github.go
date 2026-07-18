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
