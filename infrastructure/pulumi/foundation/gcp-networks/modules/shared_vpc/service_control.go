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

package shared_vpc

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/accesscontextmanager"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumiverse/pulumi-time/sdk/go/time"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network/v2"
	vpc_sc "github.com/VitruvianSoftware/pulumi-library/go/pkg/vpc_service_controls"
)

// resolvePolicyID returns the configured ACM policy override, or the 1-org
// StackReference export when no override is set.
func resolvePolicyID(args *Args) pulumi.StringInput {
	if args.PolicyID != "" {
		return pulumi.String(args.PolicyID)
	}
	return args.OrgStack.GetStringOutput(pulumi.String("access_context_manager_policy_id"))
}

// createHubServiceControl provisions the hub VPC-SC perimeter, mirroring upstream
// shared_vpc/service_control.tf.
func createHubServiceControl(ctx *pulumi.Context, args *Args) error {
	_, err := vpc_sc.NewVpcServiceControls(ctx, "hub-vpc-sc-perimeter", &vpc_sc.VpcServiceControlsArgs{
		PolicyID:           resolvePolicyID(args),
		Prefix:             "c_hub",
		Members:            args.VpcScMembers,
		MembersDryRun:      args.VpcScMembers,
		ProjectNumbers:     pulumi.StringArray{args.OrgStack.GetStringOutput(pulumi.String("net_hub_project_number"))},
		RestrictedServices: args.VpcScRestrictedServices,
		Enforce:            args.EnforceVpcSc,
	})
	return err
}

// createSpokeServiceControl provisions the spoke VPC-SC perimeter, the 60s
// propagation wait, and the spoke->hub bridge perimeter, mirroring upstream
// shared_vpc/service_control.tf. It also emits the VPC-SC exports.
func createSpokeServiceControl(ctx *pulumi.Context, args *Args, vpc *networking.Networking) error {
	policyID := resolvePolicyID(args)
	acmPolicyID := args.OrgStack.GetStringOutput(pulumi.String("access_context_manager_policy_id"))

	// Spoke/hub project numbers for VPC-SC perimeter + bridge.
	spokeProjectNumber := args.OrgStack.GetStringOutput(pulumi.String(fmt.Sprintf("%s_network_project_number", args.Env)))
	hubProjectNumber := args.OrgStack.GetStringOutput(pulumi.String("net_hub_project_number"))

	perimeter, err := vpc_sc.NewVpcServiceControls(ctx, "vpc-sc-perimeter", &vpc_sc.VpcServiceControlsArgs{
		PolicyID:           policyID,
		Prefix:             fmt.Sprintf("%s_spoke", args.Code),
		Members:            args.VpcScMembers,
		MembersDryRun:      args.VpcScMembers,
		ProjectNumbers:     pulumi.StringArray{spokeProjectNumber},
		RestrictedServices: args.VpcScRestrictedServices,
		Enforce:            args.EnforceVpcSc,
	})
	if err != nil {
		return err
	}

	// VPC-SC propagation wait — matching upstream time_sleep 60s create + 60s destroy
	vpcScSleep, err := time.NewSleep(ctx, "vpc-sc-propagation-wait", &time.SleepArgs{
		CreateDuration:  pulumi.String("60s"),
		DestroyDuration: pulumi.String("60s"),
	}, pulumi.DependsOn([]pulumi.Resource{
		perimeter.Perimeter,
		vpc.VPC,
	}))
	if err != nil {
		return err
	}

	// Bridge perimeter from spoke to hub (required for VPC-SC across peered VPCs)
	// Matching upstream PERIMETER_TYPE_BRIDGE — only created on spoke, not hub
	bridgeName := fmt.Sprintf("spb_c_to_%s_spoke_bridge", args.Code)
	// A dry-run foundation keeps the bridge's members in the dry-run Spec and leaves the
	// enforced Status empty; only populate Status when EnforceVpcSc. This mirrors the
	// regular perimeter (vpc_service_controls module, which sets Status only when
	// enforcing). GCP rejects an ENFORCED bridge member whose regular perimeter is
	// dry-run-only ("projects/... is in service perimeter bridge(s) ... but not in a
	// regular service perimeter"), so the bridge's enforcement must match the regular
	// perimeter's.
	bridgeResources := pulumi.StringArray{
		pulumi.Sprintf("projects/%s", spokeProjectNumber),
		pulumi.Sprintf("projects/%s", hubProjectNumber),
	}
	bridgeArgs := &accesscontextmanager.ServicePerimeterArgs{
		PerimeterType:         pulumi.String("PERIMETER_TYPE_BRIDGE"),
		Parent:                pulumi.Sprintf("accessPolicies/%s", policyID),
		Name:                  pulumi.Sprintf("accessPolicies/%s/servicePerimeters/%s", policyID, bridgeName),
		Title:                 pulumi.String(bridgeName),
		UseExplicitDryRunSpec: pulumi.Bool(!args.EnforceVpcSc),
		Spec:                  &accesscontextmanager.ServicePerimeterSpecArgs{Resources: bridgeResources},
	}
	if args.EnforceVpcSc {
		bridgeArgs.Status = &accesscontextmanager.ServicePerimeterStatusArgs{Resources: bridgeResources}
	}
	if _, err := accesscontextmanager.NewServicePerimeter(ctx, "vpc-sc-bridge", bridgeArgs, pulumi.DependsOn([]pulumi.Resource{vpcScSleep})); err != nil {
		return err
	}

	// VPC-SC exports
	perimeterName := pulumi.All(vpcScSleep.ID(), perimeter.Perimeter.Name).ApplyT(func(args []interface{}) string {
		return args[1].(string)
	}).(pulumi.StringOutput)

	ctx.Export("access_context_manager_policy_id", acmPolicyID)
	ctx.Export("enforce_vpcsc", pulumi.Bool(args.EnforceVpcSc))
	ctx.Export("service_perimeter_name", perimeterName)
	ctx.Export("access_level_name", perimeter.AccessLevel.Name)
	ctx.Export("access_level_name_dry_run", perimeter.AccessLevelDryRun.Name)

	return nil
}
