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

// Foundation stage 3 (networks, svpc) — thin env root for the nonproduction
// environment, mirroring upstream terraform-example-foundation
// 3-networks-svpc/envs/nonproduction. This leaf pins the environment identity
// (nonproduction/n) and calls the shared base_env module; all resource creation
// lives in ../../modules/base_env. The shared/global resources (hierarchical
// firewall) live in the sibling envs/shared leaf.
package main

import (
	"foundation-3-networks-svpc/modules/base_env"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Environment identity pinned by this leaf project — upstream
// 3-networks-svpc/envs/nonproduction hardcodes env = "nonproduction" in its
// main.tf; the leaf dir is the pin, not per-stack config.
const (
	pinnedEnv     = "nonproduction"
	pinnedEnvCode = "n"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := loadNetConfig(ctx)

		res, err := base_env.New(ctx, &base_env.Args{
			Env:     pinnedEnv,
			EnvCode: pinnedEnvCode,

			ProjectID: cfg.ProjectID,

			Region1: cfg.Region1,
			Region2: cfg.Region2,

			Domain:       cfg.Domain,
			DNSProjectID: cfg.DNSProjectID,

			OrgStackName: cfg.OrgStackName,

			PolicyID:                   cfg.PolicyID,
			VpcScMembers:               cfg.VpcScMembers,
			VpcScProjects:              cfg.VpcScProjects,
			VpcScRestrictedServices:    cfg.VpcScRestrictedServices,
			VpcScIngressPolicies:       cfg.VpcScIngressPolicies,
			VpcScEgressPolicies:        cfg.VpcScEgressPolicies,
			VpcScIngressPoliciesDryRun: cfg.VpcScIngressPoliciesDryRun,
			VpcScEgressPoliciesDryRun:  cfg.VpcScEgressPoliciesDryRun,
			EnforceVpcSc:               cfg.EnforceVpcSc,

			PscIP: cfg.PscIP,

			BgpAsn:          cfg.BgpAsn,
			NatBgpAsn:       cfg.NatBgpAsn,
			NatNumAddresses: cfg.NatNumAddresses,
			NatEnabled:      cfg.NatEnabled,

			TargetNameServers:             cfg.TargetNameServers,
			FirewallPoliciesEnableLogging: cfg.FirewallPoliciesEnableLogging,
			DnsEnableLogging:              cfg.DnsEnableLogging,

			WindowsActivationEnabled: cfg.WindowsActivationEnabled,

			FlowLogsInterval: cfg.VpcFlowLogs.AggregationInterval,
			FlowLogsSampling: cfg.VpcFlowLogs.FlowSampling,
			FlowLogsMetadata: cfg.VpcFlowLogs.Metadata,
		})
		if err != nil {
			return err
		}
		if err != nil {
			return err
		}

		// Exports — matching TF 3-networks-svpc/envs/{env}/outputs.tf
		// (outputs.go).
		exportOutputs(ctx, cfg, res)

		return nil
	})
}
