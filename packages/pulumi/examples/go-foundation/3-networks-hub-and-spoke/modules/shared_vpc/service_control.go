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

package shared_vpc

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/accesscontextmanager"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumiverse/pulumi-time/sdk/go/time"

	vpc_sc "github.com/VitruvianSoftware/pulumi-library/go/pkg/vpc_service_controls"
)

// createHubServiceControl provisions the hub VPC-SC perimeter, mirroring the
// example's envs/shared service control. It is created once on the hub project
// and reads project numbers / ACM policy from the 1-org stack reference.
func createHubServiceControl(ctx *pulumi.Context, args *Args) error {
	if args.OrgStackName == "" {
		return nil
	}

	hubOrgStack, err := pulumi.NewStackReference(ctx, "org", &pulumi.StackReferenceArgs{
		Name: pulumi.String(args.OrgStackName),
	})
	if err != nil {
		return err
	}

	var hubPolicyID pulumi.StringInput = hubOrgStack.GetStringOutput(pulumi.String("access_context_manager_policy_id"))
	if args.PolicyID != "" {
		hubPolicyID = pulumi.String(args.PolicyID)
	}

	_, err = vpc_sc.NewVpcServiceControls(ctx, "hub-vpc-sc-perimeter", &vpc_sc.VpcServiceControlsArgs{
		PolicyID:           hubPolicyID,
		Prefix:             "c_hub",
		Members:            args.VpcScMembers,
		ProjectNumbers:     pulumi.StringArray{hubOrgStack.GetStringOutput(pulumi.String("net_hub_project_number"))},
		RestrictedServices: args.VpcScRestrictedServices,
		Enforce:            args.EnforceVpcSc,
	})
	return err
}

// createSpokeServiceControl provisions the spoke VPC-SC perimeter, the 60s
// propagation wait, and the spoke->hub bridge perimeter, mirroring the example's
// envs/{env} service control. It also emits the VPC-SC exports.
func createSpokeServiceControl(ctx *pulumi.Context, args *Args) error {
	var acmPolicyID pulumi.StringOutput
	if args.OrgStackName != "" {
		orgStack, err := pulumi.NewStackReference(ctx, "org", &pulumi.StackReferenceArgs{
			Name: pulumi.String(args.OrgStackName),
		})
		if err != nil {
			return err
		}
		acmPolicyID = orgStack.GetStringOutput(pulumi.String("access_context_manager_policy_id"))
	} else {
		acmPolicyID = pulumi.String("").ToStringOutput()
	}

	var finalPolicyID pulumi.StringInput
	if args.PolicyID != "" {
		finalPolicyID = pulumi.String(args.PolicyID)
	} else {
		finalPolicyID = acmPolicyID
	}

	perimeter, err := vpc_sc.NewVpcServiceControls(ctx, "vpc-sc-perimeter", &vpc_sc.VpcServiceControlsArgs{
		PolicyID:              finalPolicyID,
		Prefix:                fmt.Sprintf("%s_spoke", args.Code),
		Members:               args.VpcScMembers,
		MembersDryRun:         args.VpcScMembers,
		ProjectNumbers:        pulumi.ToStringArray(args.VpcScProjects),
		RestrictedServices:    args.VpcScRestrictedServices,
		Enforce:               args.EnforceVpcSc,
		IngressPolicies:       args.VpcScIngressPolicies,
		EgressPolicies:        args.VpcScEgressPolicies,
		IngressPoliciesDryRun: args.VpcScIngressPoliciesDryRun,
		EgressPoliciesDryRun:  args.VpcScEgressPoliciesDryRun,
	})
	if err != nil {
		return err
	}

	vpcScSleep, err := time.NewSleep(ctx, "vpc-sc-propagation-wait", &time.SleepArgs{
		CreateDuration:  pulumi.String("60s"),
		DestroyDuration: pulumi.String("60s"),
	}, pulumi.DependsOn([]pulumi.Resource{perimeter.Perimeter}))
	if err != nil {
		return err
	}

	perimeterName := pulumi.All(vpcScSleep.ID(), perimeter.Perimeter.Name).ApplyT(func(args []interface{}) string {
		return args[1].(string)
	}).(pulumi.StringOutput)

	accessLevelName := perimeter.AccessLevel.Name
	accessLevelDryRunName := perimeter.AccessLevelDryRun.Name

	// Bridge perimeter from spoke to hub
	if args.OrgStackName != "" {
		bridgeOrgStack, bErr := pulumi.NewStackReference(ctx, "org-bridge", &pulumi.StackReferenceArgs{
			Name: pulumi.String(args.OrgStackName),
		})
		if bErr != nil {
			return bErr
		}
		hubProjectNumber := bridgeOrgStack.GetStringOutput(pulumi.String("net_hub_project_number"))

		_, bErr = accesscontextmanager.NewServicePerimeter(ctx, "vpc-sc-bridge-spoke-to-hub", &accesscontextmanager.ServicePerimeterArgs{
			Parent:        pulumi.Sprintf("accessPolicies/%s", finalPolicyID),
			Name:          pulumi.Sprintf("accessPolicies/%s/servicePerimeters/sp_%s_spoke_to_hub_bridge", finalPolicyID, args.Code),
			Title:         pulumi.Sprintf("sp_%s_spoke_to_hub_bridge", args.Code),
			PerimeterType: pulumi.String("PERIMETER_TYPE_BRIDGE"),
			Status: &accesscontextmanager.ServicePerimeterStatusArgs{
				Resources: pulumi.StringArray{
					pulumi.Sprintf("projects/%s", args.VpcScProjects[0]),
					pulumi.Sprintf("projects/%s", hubProjectNumber),
				},
			},
		}, pulumi.DependsOn([]pulumi.Resource{vpcScSleep}))
		if bErr != nil {
			return bErr
		}
	}

	// VPC-SC exports
	ctx.Export("access_context_manager_policy_id", acmPolicyID)
	ctx.Export("enforce_vpcsc", pulumi.Bool(args.EnforceVpcSc))
	ctx.Export("service_perimeter_name", perimeterName)
	ctx.Export("access_level_name", accessLevelName)
	ctx.Export("access_level_name_dry_run", accessLevelDryRunName)

	return nil
}
