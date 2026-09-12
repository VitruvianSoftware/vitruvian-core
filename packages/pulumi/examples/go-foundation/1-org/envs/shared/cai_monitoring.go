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

package main

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"foundation-1-org/modules/cai_monitoring"
)

// deployCAIMonitoring deploys the Cloud Asset Inventory monitoring
// infrastructure (Gap 2) by calling the cai_monitoring module. This mirrors
// the Terraform foundation's cai_monitoring.tf, which invokes
// module "cai_monitoring" (source = "../../modules/cai-monitoring") gated on
// enable_scc_resources_in_terraform. Returns nil when SCC resources are
// disabled.
func deployCAIMonitoring(ctx *pulumi.Context, cfg *OrgConfig, proj *OrgProjects) (*cai_monitoring.Result, error) {
	if !cfg.EnableSCCResources {
		return nil, nil
	}
	return cai_monitoring.New(ctx, "cai-monitoring", &cai_monitoring.Args{
		OrgID:         cfg.OrgID,
		DefaultRegion: cfg.DefaultRegion,
		SCCProjectID:  proj.SCCProjectID,
	})
}
