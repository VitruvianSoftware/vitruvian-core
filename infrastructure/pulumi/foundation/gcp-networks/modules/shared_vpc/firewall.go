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
