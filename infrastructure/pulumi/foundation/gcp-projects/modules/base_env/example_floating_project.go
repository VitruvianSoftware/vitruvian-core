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
		}
		// Site Verification API — DEV oss floating project ONLY. The
		// oauth-user-inspector custom-domain verification is SHARED: the DEV
		// deploy SA calls the Site Verification write API (getToken/insert) with
		// this project as its quota project, self-verifies the zone, and
		// delegates all three env deploy SAs as owners — so nonprod/prod never
		// call the write API and do not need it. It is enabled HERE, in the
		// project's own foundation-managed API list (applied as the project
		// owner), because an additive enable later as the app's deploy identity
		// lacks serviceusage rights on the project (the app stack cannot enable
		// it; PR #949's attempt failed for exactly that reason). Enabling one
		// more API the app's OWN project needs is normal project config, not the
		// shared-infra-pipeline coupling objected to in #938.
		if args.EnvCode == "d" {
			ossApis = append(ossApis, "siteverification.googleapis.com")
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
