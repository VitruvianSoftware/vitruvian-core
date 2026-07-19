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
	"fmt"
	"foundation-3-networks-hub-and-spoke/modules/shared_vpc"
	"foundation-3-networks-hub-and-spoke/modules/transitivity"

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
		EnvCode:     pinnedEnvCode,
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
