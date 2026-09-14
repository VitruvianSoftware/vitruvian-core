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
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/accesscontextmanager"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network/v2"
)

// Args are the inputs to the shared_vpc module. Fields common to both hub and
// spoke are always populated; the caller sets Mode/Code to select the naming
// scheme and the mode-specific resources (peering + bridge on spoke, BGP routers
// + forwarding zone on hub).
type Args struct {
	Mode string // "hub" or "spoke"
	Code string // env_code ("c" for hub, "d"/"n"/"p" for spoke)

	// Projects & cross-stage references.
	ProjectID    pulumi.StringInput  // host project (hub or spoke)
	HubProjectID pulumi.StringOutput // hub host project — used by spoke peering ref
	OrgStackName string              // 1-org stack name (VPC-SC stack references)

	// VPC + subnets (built by the caller).
	VPCName             string
	Subnets             []networking.SubnetArgs
	FirewallSubnetCidrs []string // primary subnet CIDRs, for the foundation firewall rules

	// Regions (router loops).
	Region1 string
	Region2 string

	// Private Service Connect.
	PscIP string

	// Logging toggles.
	FirewallPoliciesEnableLogging bool
	DnsEnableLogging              bool

	// DNS.
	Domain            string
	TargetNameServers []string // hub forwarding zone only

	// Routes.
	WindowsActivationEnabled bool

	// NAT (caller passes HubNatEnabled for hub, NatEnabled for spoke).
	NatEnabled      bool
	NatBgpAsn       int
	NatNumAddresses int

	// BGP (hub only).
	BgpAsn int

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
