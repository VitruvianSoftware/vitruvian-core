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
	"fmt"

	"foundation-networks/modules/shared_vpc"
	"foundation-networks/modules/transitivity"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// deployNetHubsTransitivity provisions the hub transitivity appliance,
// mirroring upstream 3-networks-hub-and-spoke/envs/shared/
// net-hubs-transitivity.tf. It is conditional on
// enable_hub_and_spoke_transitivity (default false, matching upstream).
func deployNetHubsTransitivity(ctx *pulumi.Context, cfg *NetSharedConfig, hubProjectID pulumi.StringOutput, hubRes *shared_vpc.Result, hubVpcName string) error {
	if !cfg.EnableHubAndSpokeTransitivity {
		return nil
	}
	return transitivity.New(ctx, &transitivity.Args{
		ProjectID:   hubProjectID,
		Region1:     cfg.Region1,
		Region2:     cfg.Region2,
		Network:     hubRes.Networking.VPC.SelfLink,
		NetworkName: hubVpcName,
		Subnetworks: map[string]pulumi.StringInput{
			cfg.Region1: hubRes.Networking.Subnets[fmt.Sprintf("sb-%s-svpc-hub-%s", pinnedEnvCode, cfg.Region1)].SelfLink,
			cfg.Region2: hubRes.Networking.Subnets[fmt.Sprintf("sb-%s-svpc-hub-%s", pinnedEnvCode, cfg.Region2)].SelfLink,
		},
		FirewallPolicy: hubRes.Firewall.Policy.Name,
		VPC:            hubRes.Networking.VPC,
	})
}
