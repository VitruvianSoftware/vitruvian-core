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

// Package base_env is the Pulumi port of upstream terraform-example-foundation
// 3-networks-hub-and-spoke/modules/base_env. It is the thin per-environment
// spoke orchestrator: it builds the spoke subnet args (secondary ranges only on
// R1, matching upstream) and invokes the shared_vpc module in "spoke" mode.
package base_env

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/accesscontextmanager"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network/v2"

	"foundation-3-networks-hub-and-spoke/modules/shared_vpc"
)

// Args are the inputs to the base_env (spoke) module — the per-environment
// identity, the spoke CIDR plan, and the shared network toggles.
type Args struct {
	Env     string
	EnvCode string

	// Projects & cross-stage references.
	ProjectID    pulumi.StringInput  // spoke Shared VPC host project
	HubProjectID pulumi.StringOutput // hub host project (peering ref)
	OrgStackName string

	// Regions.
	Region1 string
	Region2 string

	// Spoke CIDRs (secondary ranges only on R1, matching upstream).
	Subnet1Cidr string
	Subnet2Cidr string
	Proxy1Cidr  string
	Proxy2Cidr  string
	GkePod1Cidr string
	GkeSvc1Cidr string

	// VPC flow logs.
	FlowLogsInterval string
	FlowLogsSampling float64
	FlowLogsMetadata string

	// Private Service Connect.
	PscIP string

	// Logging toggles.
	FirewallPoliciesEnableLogging bool
	DnsEnableLogging              bool

	// DNS.
	Domain string

	// Feature toggles.
	WindowsActivationEnabled bool
	NatEnabled               bool
	NatBgpAsn                int
	NatNumAddresses          int

	// VPC Service Controls.
	PolicyID                   string
	VpcScMembers               []string
	VpcScProjects              []string
	VpcScRestrictedServices    []string
	EnforceVpcSc               bool
	VpcScIngressPolicies       accesscontextmanager.ServicePerimeterStatusIngressPolicyArray
	VpcScEgressPolicies        accesscontextmanager.ServicePerimeterStatusEgressPolicyArray
	VpcScIngressPoliciesDryRun accesscontextmanager.ServicePerimeterSpecIngressPolicyArray
	VpcScEgressPoliciesDryRun  accesscontextmanager.ServicePerimeterSpecEgressPolicyArray
}

// Result holds the spoke network outputs consumed by the stage root exports.
type Result struct {
	Networking *networking.Networking
}

// New builds the spoke subnet args and deploys the spoke Shared VPC via the
// shared_vpc module (Mode: "spoke"). opts serialises the spoke behind the hub
// VPC when both are created in the same run.
func New(ctx *pulumi.Context, args *Args, opts ...pulumi.ResourceOption) (*Result, error) {
	envCode := args.EnvCode

	// Spoke VPC & Subnets — secondary ranges only on R1 (matching upstream).
	vpcName := fmt.Sprintf("vpc-%s-svpc-spoke", envCode)
	subnets := []networking.SubnetArgs{
		{
			Name:   fmt.Sprintf("sb-%s-svpc-spoke-%s", envCode, args.Region1),
			Region: args.Region1,
			CIDR:   args.Subnet1Cidr,
			SecondaryRanges: []networking.SecondaryRangeArgs{
				{RangeName: fmt.Sprintf("rn-%s-spoke-%s-gke-pod", envCode, args.Region1), CIDR: args.GkePod1Cidr},
				{RangeName: fmt.Sprintf("rn-%s-spoke-%s-gke-svc", envCode, args.Region1), CIDR: args.GkeSvc1Cidr},
			},
			FlowLogs:         true,
			FlowLogsInterval: args.FlowLogsInterval,
			FlowLogsSampling: args.FlowLogsSampling,
			FlowLogsMetadata: args.FlowLogsMetadata,
		},
		{
			Name:   fmt.Sprintf("sb-%s-svpc-spoke-%s", envCode, args.Region2),
			Region: args.Region2,
			CIDR:   args.Subnet2Cidr,
			// No secondary ranges on R2 (matching upstream)
			FlowLogs:         true,
			FlowLogsInterval: args.FlowLogsInterval,
			FlowLogsSampling: args.FlowLogsSampling,
			FlowLogsMetadata: args.FlowLogsMetadata,
		},
		{
			Name:    fmt.Sprintf("sb-%s-svpc-spoke-%s-proxy", envCode, args.Region1),
			Region:  args.Region1,
			CIDR:    args.Proxy1Cidr,
			Role:    "ACTIVE",
			Purpose: "REGIONAL_MANAGED_PROXY",
		},
		{
			Name:    fmt.Sprintf("sb-%s-svpc-spoke-%s-proxy", envCode, args.Region2),
			Region:  args.Region2,
			CIDR:    args.Proxy2Cidr,
			Role:    "ACTIVE",
			Purpose: "REGIONAL_MANAGED_PROXY",
		},
	}

	res, err := shared_vpc.New(ctx, &shared_vpc.Args{
		Mode: "spoke",
		Code: envCode,

		ProjectID:    args.ProjectID,
		HubProjectID: args.HubProjectID,
		OrgStackName: args.OrgStackName,

		VPCName:             vpcName,
		Subnets:             subnets,
		FirewallSubnetCidrs: []string{args.Subnet1Cidr, args.Subnet2Cidr},

		Region1: args.Region1,
		Region2: args.Region2,

		PscIP: args.PscIP,

		FirewallPoliciesEnableLogging: args.FirewallPoliciesEnableLogging,
		DnsEnableLogging:              args.DnsEnableLogging,

		Domain: args.Domain,

		WindowsActivationEnabled: args.WindowsActivationEnabled,

		NatEnabled:      args.NatEnabled,
		NatBgpAsn:       args.NatBgpAsn,
		NatNumAddresses: args.NatNumAddresses,

		PolicyID:                   args.PolicyID,
		VpcScMembers:               args.VpcScMembers,
		VpcScProjects:              args.VpcScProjects,
		VpcScRestrictedServices:    args.VpcScRestrictedServices,
		EnforceVpcSc:               args.EnforceVpcSc,
		VpcScIngressPolicies:       args.VpcScIngressPolicies,
		VpcScEgressPolicies:        args.VpcScEgressPolicies,
		VpcScIngressPoliciesDryRun: args.VpcScIngressPoliciesDryRun,
		VpcScEgressPoliciesDryRun:  args.VpcScEgressPoliciesDryRun,
	}, opts...)
	if err != nil {
		return nil, err
	}

	return &Result{Networking: res.Networking}, nil
}
