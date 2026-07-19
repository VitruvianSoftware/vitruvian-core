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
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network/v2"
)

// Args are the inputs to the shared_vpc module. Fields common to both hub and
// spoke are always populated; the caller sets Mode/Code to select the naming
// scheme and the mode-specific resources (peering + bridge on spoke, BGP
// routers + forwarding zone on hub).
type Args struct {
	Mode string // "hub" or "spoke"
	Code string // "c" for hub, environment code ("d"/"n"/"p") for spoke

	// Projects & cross-stage references.
	ProjectID    pulumi.StringInput     // host project (hub or spoke)
	HubProjectID pulumi.StringOutput    // hub host project — used by spoke peering ref + bridge
	OrgStack     *pulumi.StackReference // 1-org exports (project numbers, ACM policy)
	Env          string                 // full env name, for spoke stack-output keys

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
	PolicyID                string
	VpcScMembers            []string
	VpcScRestrictedServices []string
	EnforceVpcSc            bool
}
