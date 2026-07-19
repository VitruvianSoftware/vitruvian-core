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

// Org-stage service accounts. This mirrors the Terraform foundation's
// 1-org/envs/shared/sa.tf, which creates only the cai-monitoring-builder
// service account (the stage pipeline SAs themselves live in 0-bootstrap).

package main

import (
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// deployCAIMonitoringBuilderSA creates the dedicated service account used by
// Cloud Build to provision the CAI monitoring Cloud Function (G4+G5).
//
// Cold-deploy fix: this SA must exist BEFORE the CAI monitoring Cloud
// Function references it as the Cloud Build SA — a string-built email with no
// dependency edge guarantees a "service account does not exist" failure on a
// fresh apply. It is created here (moved from iam.go section 11; same logical
// name so the URN is unchanged), gated on the SCC project's ApisReady, and
// passed as a resource into the cai_monitoring module (cai_monitoring.go) and
// into deployOrgIAM for its role bindings (iam.go).
//
// Returns nil when SCC resources are disabled.
func deployCAIMonitoringBuilderSA(ctx *pulumi.Context, cfg *OrgConfig, proj *OrgProjects) (*serviceaccount.Account, error) {
	if !cfg.EnableSCCResources {
		return nil, nil
	}
	var saOpts []pulumi.ResourceOption
	if proj.SCCApisReady != nil {
		// IAM API propagation gate on the freshly-created SCC project.
		saOpts = append(saOpts, pulumi.DependsOn([]pulumi.Resource{proj.SCCApisReady}))
	}
	return serviceaccount.NewAccount(ctx, "cai-monitoring-builder", &serviceaccount.AccountArgs{
		Project:     proj.SCCProjectID,
		AccountId:   pulumi.String("cai-monitoring-builder"),
		Description: pulumi.String("Service account for Cloud Build to provision CAI monitoring Cloud Functions"),
	}, saOpts...)
}
