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
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/dns"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network/v2"
)

// createDNSPolicy provisions the inbound-forwarding DNS policy, mirroring
// upstream shared_vpc/dns.tf google_dns_policy.default_policy.
func createDNSPolicy(ctx *pulumi.Context, args *Args, vpc *networking.Networking) (*dns.Policy, error) {
	resourceName := fmt.Sprintf("%s-dns-policy", args.Mode)
	policy, err := dns.NewPolicy(ctx, resourceName, &dns.PolicyArgs{
		Project:                 args.ProjectID,
		Name:                    pulumi.String(fmt.Sprintf("dp-%s-%s-default-policy", args.Code, args.Mode)),
		EnableInboundForwarding: pulumi.Bool(true),
		EnableLogging:           pulumi.Bool(args.DnsEnableLogging),
		Networks: dns.PolicyNetworkArray{
			&dns.PolicyNetworkArgs{
				NetworkUrl: vpc.VPC.SelfLink,
			},
		},
	}, pulumi.DependsOn([]pulumi.Resource{vpc.VPC}))
	if err != nil {
		return nil, err
	}
	return policy, nil
}

// createDNSForwardingZone provisions the hub forwarding zone (conditional on
// target_name_servers), mirroring upstream shared_vpc/dns.tf.
func createDNSForwardingZone(ctx *pulumi.Context, args *Args, vpc *networking.Networking) error {
	_, err := networking.NewDnsZone(ctx, "dns-forwarding", &networking.DnsZoneArgs{
		ProjectID:                 args.ProjectID,
		Name:                      "fz-dns-hub",
		Domain:                    args.Domain,
		Type:                      "forwarding",
		NetworkSelfLink:           vpc.VPC.SelfLink,
		TargetNameServerAddresses: args.TargetNameServers,
	})
	return err
}

// createDNSPeeringZone provisions the spoke->hub DNS peering zone, mirroring
// upstream shared_vpc/dns.tf. opts serialises it behind the hub VPC.
func createDNSPeeringZone(ctx *pulumi.Context, args *Args, vpc *networking.Networking, opts ...pulumi.ResourceOption) error {
	hubVpcRef := pulumi.Sprintf("projects/%s/global/networks/vpc-c-svpc-hub", args.HubProjectID)
	_, err := networking.NewDnsZone(ctx, "dns-peering", &networking.DnsZoneArgs{
		ProjectID:             args.ProjectID,
		Name:                  fmt.Sprintf("dz-%s-svpc-spoke-to-dns-hub", args.Code),
		Domain:                args.Domain,
		Type:                  "peering",
		NetworkSelfLink:       vpc.VPC.SelfLink,
		TargetNetworkSelfLink: hubVpcRef,
	}, opts...)
	return err
}
