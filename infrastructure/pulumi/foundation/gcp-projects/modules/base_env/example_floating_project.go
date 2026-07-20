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

package base_env

import (
	"fmt"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"foundation-projects/modules/single_project"
)

// deployFloatingProject creates the floating project (not attached to any
// VPC), matching upstream's example_floating_project.tf (toggle-gated), plus
// the monorepo-specific OSS floating project (separately toggle-gated below).
func deployFloatingProject(ctx *pulumi.Context, args *Args, result *BUProjects) error {
	if !args.FloatingProjectEnabled {
		return nil
	}

	floatingProject, err := single_project.New(ctx, "bu-floating-project", &single_project.Args{
		DefaultServiceAccount: "disable", // upstream default; see the svpc project
		ProjectID:             fmt.Sprintf("%s-%s-%s-sample-floating", args.ProjectPrefix, args.EnvCode, args.BusinessCode),
		FolderID:              args.FolderID,
		BillingAccount:        args.BillingAccount,
		RandomProjectID:       args.RandomSuffix,
		Labels:                args.Labels("sample-application", "none"),
		Budget:                args.Budget,
		ActivateApis: []string{
			"compute.googleapis.com",
			"container.googleapis.com",
			"run.googleapis.com",
			"artifactregistry.googleapis.com",
			"billingbudgets.googleapis.com",
			"logging.googleapis.com",
		},
		ApiPropagationSeconds: args.ApiPropagationSeconds,
	})
	if err != nil {
		return err
	}
	result.FloatingProjectID = floatingProject.ProjectID

	// OSS Floating Project (not attached to any VPC, toggle-gated)
	// A second floating project in the same BU folder, dedicated to hosting the
	// monorepo's open-source applications (e.g. oauth-user-inspector) on
	// org-managed infrastructure instead of a personal-account project. Distinct
	// from the -sample-floating reference project above.
	if args.OSSFloatingProjectEnabled {
		ossApis := []string{
			"compute.googleapis.com",
			"container.googleapis.com",
			"run.googleapis.com",
			"artifactregistry.googleapis.com",
			"billingbudgets.googleapis.com",
			"logging.googleapis.com",
			// Stage-5 app-tier (serverless OSS apps deployed here via WIF):
			// secretmanager for per-app runtime secrets; iam for the app
			// deploy/runtime service accounts; iamcredentials so a WIF-federated
			// job can mint an access token by impersonating a deploy SA homed
			// in this project. (Monorepo/serverless-WIF specific — upstream's
			// VM/Cloud-Build model does not need these, so they are not in the
			// go-foundation example.)
			"secretmanager.googleapis.com",
			"iam.googleapis.com",
			"iamcredentials.googleapis.com",
			// Site Verification API — required on ALL THREE oss floating
			// projects. oauth-user-inspector custom-domain verification is
			// PER-ENV SELF-VERIFICATION: each env's deploy SA calls the Site
			// Verification write API (getToken/insert) with ITS OWN floating
			// project as the quota project and self-verifies the Cloudflare
			// zone via DNS-TXT before its Cloud Run DomainMapping deploy.
			// Ownership in that service is per-caller — no SA can verify (or
			// delegate) on another identity's behalf — so every env needs the
			// API on its own project (see tools/ci/ensure-site-verification.sh).
			//
			// ⚠️ CONSOLE-ONLY API — MUST BE ENABLED BY HAND ONCE PER PROJECT.
			// Unlike every other API in this list,
			// siteverification.googleapis.com CANNOT be enabled via
			// serviceusage/IaC: even the project-owner SA that applies this
			// stack gets HTTP 403 PreconditionFailure ("failed on request
			// preconditions"). It has to be enabled once, by a human, in the
			// console, per floating project:
			//   https://console.cloud.google.com/apis/library/siteverification.googleapis.com?project=<PROJECT_ID>
			// Status: prj-d-bu1-oss-floating-648a is DONE; still to click:
			//   https://console.cloud.google.com/apis/library/siteverification.googleapis.com?project=prj-n-bu1-oss-floating-630b
			//   https://console.cloud.google.com/apis/library/siteverification.googleapis.com?project=prj-p-bu1-oss-floating-16e0
			// This ActivateApis entry therefore does NOT do the enabling — it
			// exists so that, AFTER the manual enable, the project's API set
			// still matches this declared config and the entry converges to a
			// no-op (rather than a perpetual add). Do not be misled into
			// thinking a fresh floating project gets this API from IaC alone;
			// the manual console enable is required.
			"siteverification.googleapis.com",
		}
		ossFloatingProject, err := single_project.New(ctx, "bu-oss-floating-project", &single_project.Args{
			DefaultServiceAccount: "disable", // upstream default; see the svpc project
			ProjectID:             fmt.Sprintf("%s-%s-%s-oss-floating", args.ProjectPrefix, args.EnvCode, args.BusinessCode),
			FolderID:              args.FolderID,
			BillingAccount:        args.BillingAccount,
			RandomProjectID:       args.RandomSuffix,
			Labels:                args.Labels("oss-application", "none"),
			Budget:                args.Budget,
			ActivateApis:          ossApis,
			ApiPropagationSeconds: args.ApiPropagationSeconds,
		})
		if err != nil {
			return err
		}
		result.OSSFloatingProjectID = ossFloatingProject.ProjectID
		result.OSSFloatingProjectNumber = ossFloatingProject.ProjectNumber
	}

	return nil
}
