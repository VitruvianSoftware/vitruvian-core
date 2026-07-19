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

package main

import (
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"foundation-org/modules/cai_monitoring"
)

// deployCAIMonitoring deploys the Cloud Asset Inventory monitoring
// infrastructure (Gap 2) by calling the cai_monitoring module. This mirrors
// the Terraform foundation's cai_monitoring.tf, which invokes
// module "cai_monitoring" (source = "../../modules/cai-monitoring") gated on
// enable_scc_resources_in_terraform. Returns nil when SCC resources are
// disabled.
//
// Cold-deploy gates: the pre-created builder SA (sa.go) is passed as a
// resource so the Cloud Function build has a real dependency edge on it, and
// every child of the module waits on the SCC project's ApisReady.
func deployCAIMonitoring(ctx *pulumi.Context, cfg *OrgConfig, proj *OrgProjects, builderSA *serviceaccount.Account) (*cai_monitoring.Result, error) {
	if !cfg.EnableSCCResources {
		return nil, nil
	}
	var caiDeps []pulumi.Resource
	if proj.SCCApisReady != nil {
		caiDeps = append(caiDeps, proj.SCCApisReady)
	}
	return cai_monitoring.New(ctx, "cai-monitoring", &cai_monitoring.Args{
		OrgID:         cfg.OrgID,
		DefaultRegion: cfg.DefaultRegion,
		SCCProjectID:  proj.SCCProjectID,
		BuilderSA:     builderSA,
		Dependencies:  caiDeps,
	})
}
