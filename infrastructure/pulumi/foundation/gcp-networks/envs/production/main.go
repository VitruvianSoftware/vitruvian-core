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

// Foundation stage 3 (networks, hub-and-spoke) — thin env root for the
// production spoke, mirroring upstream terraform-example-foundation
// 3-networks-hub-and-spoke/envs/production. This leaf pins the environment
// identity (production/p) and its spoke CIDR plan, reads the host projects
// from a StackReference to 1-org, then calls the shared base_env module. All
// resource creation lives in ../../modules; the hub network lives in the
// sibling envs/shared leaf.
//
// Cross-stack peering serialization: the hub VPC (and its PSA
// servicenetworking connection) is created by the envs/shared stack, which is
// fully applied before this stack runs (deploy order shared → development →
// nonproduction → production). GCP allows only one peering-mutating operation
// at a time per VPC, so that ordering preserves the PSA-before-peering
// serialization the pre-split single-stack layout enforced with an explicit
// DependsOn on the hub PSAConnection. The spoke's own PSA-vs-peering
// serialization (spoke peering DependsOn the spoke PSAConnection) lives in
// modules/shared_vpc (createPeering).
package main

import (
	"foundation-networks/modules/base_env"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Environment identity and spoke CIDR plan pinned by this leaf project —
// upstream 3-networks-hub-and-spoke/envs/production hardcodes them in its
// main.tf; the leaf dir is the pin, not per-stack config. CIDRs derive from
// the upstream reference architecture (no overlaps across envs; secondary
// ranges only on R1, matching upstream).
const (
	pinnedEnv     = "production"
	pinnedEnvCode = "p"

	spokeSubnet1Cidr = "10.8.192.0/18"
	spokeSubnet2Cidr = "10.9.192.0/18"
	spokeProxy1Cidr  = "10.26.6.0/23"
	spokeProxy2Cidr  = "10.27.6.0/23"
	spokeGkePod1Cidr = "100.72.192.0/18"
	spokeGkeSvc1Cidr = "100.73.192.0/18"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := loadNetConfig(ctx)

		// Stack Reference to 1-org for project IDs and ACM policy (remote.go).
		org, err := lookupOrgRemote(ctx, cfg)
		if err != nil {
			return err
		}

		// =================================================================
		// SPOKE NETWORK (this environment)
		// =================================================================
		spokeOutputs, err := base_env.New(ctx, &base_env.Args{
			Env:     pinnedEnv,
			EnvCode: pinnedEnvCode,

			ProjectID:    org.spokeProjectID,
			HubProjectID: org.hubProjectID,
			OrgStack:     org.stack,

			Region1: cfg.Region1,
			Region2: cfg.Region2,

			Subnet1Cidr: spokeSubnet1Cidr,
			Subnet2Cidr: spokeSubnet2Cidr,
			Proxy1Cidr:  spokeProxy1Cidr,
			Proxy2Cidr:  spokeProxy2Cidr,
			GkePod1Cidr: spokeGkePod1Cidr,
			GkeSvc1Cidr: spokeGkeSvc1Cidr,

			FlowLogsInterval: cfg.VpcFlowLogs.AggregationInterval,
			FlowLogsSampling: cfg.VpcFlowLogs.FlowSampling,
			FlowLogsMetadata: cfg.VpcFlowLogs.Metadata,

			PscIP: cfg.PscIP,

			FirewallPoliciesEnableLogging: cfg.FirewallPoliciesEnableLogging,
			DnsEnableLogging:              cfg.DnsEnableLogging,

			Domain: cfg.Domain,

			WindowsActivationEnabled: cfg.WindowsActivationEnabled,
			NatEnabled:               cfg.NatEnabled,
			NatBgpAsn:                cfg.NatBgpAsn,
			NatNumAddresses:          cfg.NatNumAddresses,

			PolicyID:                cfg.PolicyID,
			VpcScMembers:            cfg.VpcScMembers,
			VpcScRestrictedServices: cfg.VpcScRestrictedServices,
			EnforceVpcSc:            cfg.EnforceVpcSc,
		})
		if err != nil {
			return err
		}
		if err != nil {
			return err
		}

		// =================================================================
		// Exports — matches upstream TF
		// 3-networks-hub-and-spoke/envs/{env}/outputs.tf (outputs.go)
		// =================================================================
		exportSpokeOutputs(ctx, org.spokeProjectID, spokeOutputs.Networking)

		return nil
	})
}
