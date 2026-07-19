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

package base_env

import (
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/accesscontextmanager"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
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
