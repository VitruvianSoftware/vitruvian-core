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
)

// Args are the inputs to the base_env module — the per-environment identity
// plus the network/DNS/NAT/VPC-SC settings from the leaf's stack config.
type Args struct {
	Env     string // "development" | "nonproduction" | "production"
	EnvCode string // "d" | "n" | "p"

	// Shared VPC host project for this environment.
	ProjectID string

	// Regions.
	Region1 string
	Region2 string

	// DNS.
	Domain       string
	DNSProjectID string // DNS hub project (peering target for non-prod envs)

	// Cross-stage references.
	OrgStackName string

	// VPC Service Controls.
	PolicyID                   string
	VpcScMembers               []string
	VpcScProjects              []string
	VpcScRestrictedServices    []string
	VpcScIngressPolicies       accesscontextmanager.ServicePerimeterStatusIngressPolicyArray
	VpcScEgressPolicies        accesscontextmanager.ServicePerimeterStatusEgressPolicyArray
	VpcScIngressPoliciesDryRun accesscontextmanager.ServicePerimeterSpecIngressPolicyArray
	VpcScEgressPoliciesDryRun  accesscontextmanager.ServicePerimeterSpecEgressPolicyArray
	EnforceVpcSc               bool

	// PSC.
	PscIP string

	// BGP / NAT.
	BgpAsn          int
	NatBgpAsn       int
	NatNumAddresses int
	NatEnabled      bool

	// DNS / firewall logging toggles.
	TargetNameServers             []string
	FirewallPoliciesEnableLogging bool
	DnsEnableLogging              bool

	// Routes.
	WindowsActivationEnabled bool

	// VPC flow logs.
	FlowLogsInterval string
	FlowLogsSampling float64
	FlowLogsMetadata string
}
