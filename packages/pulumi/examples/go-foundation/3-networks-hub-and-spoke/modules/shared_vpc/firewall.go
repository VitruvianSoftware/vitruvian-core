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

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network/v2"
)

// createFirewall builds the VPC-level network firewall policy, mirroring
// upstream shared_vpc/firewall.tf via the foundation rule set.
func createFirewall(ctx *pulumi.Context, args *Args, vpc *networking.Networking) (*networking.NetworkFirewallPolicy, error) {
	resourceName := fmt.Sprintf("%s-vpc-fw", args.Mode)
	fw, err := networking.NewNetworkFirewallPolicy(ctx, resourceName, &networking.NetworkFirewallPolicyArgs{
		ProjectID:  args.ProjectID,
		PolicyName: fmt.Sprintf("fp-%s-%s-firewalls", args.Code, args.Mode),
		TargetVPCs: []pulumi.StringInput{
			pulumi.Sprintf("projects/%s/global/networks/%s", args.ProjectID, vpc.VPC.Name),
		},
		Rules: networking.BuildFoundationRules(args.Code, args.FirewallPoliciesEnableLogging, args.PscIP+"/32", args.FirewallSubnetCidrs, false),
	}, pulumi.DependsOn([]pulumi.Resource{vpc.VPC}))
	if err != nil {
		return nil, err
	}
	return fw, nil
}
