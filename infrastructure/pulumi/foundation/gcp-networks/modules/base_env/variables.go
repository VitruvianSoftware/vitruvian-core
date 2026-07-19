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

package base_env

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Args are the inputs to the base_env (spoke) module — the per-environment
// identity, the spoke CIDR plan, and the shared network toggles.
type Args struct {
	Env     string
	EnvCode string

	// Projects & cross-stage references.
	ProjectID    pulumi.StringInput  // spoke Shared VPC host project
	HubProjectID pulumi.StringOutput // hub host project (peering ref + bridge)
	OrgStack     *pulumi.StackReference

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
	PolicyID                string
	VpcScMembers            []string
	VpcScRestrictedServices []string
	EnforceVpcSc            bool
}
