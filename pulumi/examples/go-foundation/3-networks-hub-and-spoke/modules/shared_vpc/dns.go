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

// createDNSForwardingZone provisions the hub forwarding zone, mirroring upstream
// shared_vpc/dns.tf.
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
// upstream shared_vpc/dns.tf.
func createDNSPeeringZone(ctx *pulumi.Context, args *Args, vpc *networking.Networking) error {
	hubVpcRef := pulumi.Sprintf("projects/%s/global/networks/vpc-c-svpc-hub", args.HubProjectID)
	_, err := networking.NewDnsZone(ctx, "dns-peering", &networking.DnsZoneArgs{
		ProjectID:             args.ProjectID,
		Name:                  fmt.Sprintf("dz-%s-svpc-spoke-to-dns-hub", args.Code),
		Domain:                args.Domain,
		Type:                  "peering",
		NetworkSelfLink:       vpc.VPC.SelfLink,
		TargetNetworkSelfLink: hubVpcRef,
	}, pulumi.DependsOn([]pulumi.Resource{vpc.VPC}))
	return err
}
