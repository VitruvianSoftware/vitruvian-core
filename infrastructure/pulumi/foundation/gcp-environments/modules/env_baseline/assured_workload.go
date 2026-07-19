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

// Optional Assured Workload — the Pulumi analog of upstream
// env_baseline/assured_workload.tf (google_assured_workloads_workload.workload).

package env_baseline

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/assuredworkloads"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/organizations"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// deployAssuredWorkload creates the optional Assured Workload for the
// environment folder. No-op unless args.AssuredWorkload.Enabled.
func deployAssuredWorkload(ctx *pulumi.Context, args *Args, envFolder *organizations.Folder, res *Result) error {
	env := args.Env

	// ========================================================================
	// 5. Assured Workload (optional) — assured_workload.tf
	// ========================================================================
	if args.AssuredWorkload.Enabled {
		workload, err := assuredworkloads.NewWorkload(ctx, fmt.Sprintf("assured-workload-%s", env), &assuredworkloads.WorkloadArgs{
			Organization:               pulumi.String(args.OrgID),
			BillingAccount:             pulumi.String(fmt.Sprintf("billingAccounts/%s", args.BillingAccount)),
			ProvisionedResourcesParent: folderIDString(envFolder),
			ComplianceRegime:           pulumi.String(args.AssuredWorkload.ComplianceRegime),
			DisplayName:                pulumi.String(args.AssuredWorkload.DisplayName),
			Location:                   pulumi.String(args.AssuredWorkload.Location),
			ResourceSettings: assuredworkloads.WorkloadResourceSettingArray{
				&assuredworkloads.WorkloadResourceSettingArgs{
					ResourceType: pulumi.String(args.AssuredWorkload.ResourceType),
				},
			},
		}, pulumi.DependsOn([]pulumi.Resource{envFolder}))
		if err != nil {
			return err
		}
		res.AssuredWorkloadID = workload.ID().ApplyT(func(id pulumi.ID) string {
			return string(id)
		}).(pulumi.StringOutput)
		res.AssuredWorkloadResources = workload.Resources
	}

	return nil
}
