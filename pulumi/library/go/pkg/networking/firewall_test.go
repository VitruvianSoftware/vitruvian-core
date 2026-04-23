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

package networking

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/require"
)

func TestNewFirewall(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		// Global policy
		_, err := NewNetworkFirewallPolicy(ctx, "test-fw-global", &NetworkFirewallPolicyArgs{
			ProjectID:  pulumi.String("test-proj"),
			PolicyName: "global-policy",
			TargetVPCs: []pulumi.StringInput{pulumi.String("vpc-1")},
			Rules: []FirewallRule{
				{
					Priority:    1000,
					Direction:   "INGRESS",
					Action:      "allow",
					Description: "Test rule",
					Match: FirewallRuleMatch{
						SrcIpRanges:            []string{"10.0.0.0/8"},
						DestIpRanges:           []string{"192.168.0.0/16"},
						SrcFqdns:               []string{"example.com"},
						SrcAddressGroups:       []string{"src-group"},
						SrcThreatIntelligences: []string{"iplist-known-malicious-ips"},
						SrcRegionCodes:         []string{"US"},
						Layer4Configs: []FirewallLayer4Config{
							{IpProtocol: "tcp", Ports: []string{"80", "443"}},
						},
						SrcSecureTags: []pulumi.StringInput{pulumi.String("tag-1")},
					},
					TargetSecureTags: []pulumi.StringInput{pulumi.String("tag-1")},
				},
				{
					Priority:    1001,
					Direction:   "EGRESS",
					Action:      "allow",
					Description: "Test egress rule",
					Match: FirewallRuleMatch{
						SrcIpRanges:             []string{"10.0.0.0/8"},
						DestIpRanges:            []string{"192.168.0.0/16"},
						DestFqdns:               []string{"dest.com"},
						DestAddressGroups:       []string{"dest-group"},
						DestThreatIntelligences: []string{"iplist-known-malicious-ips"},
						Layer4Configs: []FirewallLayer4Config{
							{IpProtocol: "tcp", Ports: []string{"80", "443"}},
						},
					},
					TargetServiceAccounts: []string{"sa@example.com"},
				},
			},
		})
		require.NoError(t, err)

		// Regional policy
		_, err = NewNetworkFirewallPolicy(ctx, "test-fw-regional", &NetworkFirewallPolicyArgs{
			ProjectID:    pulumi.String("test-proj"),
			PolicyName:   "regional-policy",
			PolicyRegion: "us-central1",
			TargetVPCs:   []pulumi.StringInput{pulumi.String("vpc-2")},
			Rules: append(BuildFoundationRules("d", true, "10.0.0.1", []string{"10.0.0.0/8"}, true), FirewallRule{
				Priority:    1001,
				Direction:   "EGRESS",
				Action:      "allow",
				Description: "Regional egress rule",
				Match: FirewallRuleMatch{
					SrcIpRanges:             []string{"10.0.0.0/8"},
					DestIpRanges:            []string{"192.168.0.0/16"},
					DestFqdns:               []string{"dest.com"},
					DestAddressGroups:       []string{"dest-group"},
					DestThreatIntelligences: []string{"iplist-known-malicious"},
					DestRegionCodes:         []string{"US"},
					SrcNetworks:             []string{"network-a"},
					Layer4Configs: []FirewallLayer4Config{
						{IpProtocol: "tcp", Ports: []string{"80"}},
					},
				},
				TargetServiceAccounts: []string{"sa@example.com"},
			}),
		})
		require.NoError(t, err)

		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:compute/networkFirewallPolicy:NetworkFirewallPolicy", 1)
	tracker.RequireType(t, "gcp:compute/networkFirewallPolicyAssociation:NetworkFirewallPolicyAssociation", 1)
	tracker.RequireType(t, "gcp:compute/networkFirewallPolicyRule:NetworkFirewallPolicyRule", 2)
	tracker.RequireType(t, "gcp:compute/regionNetworkFirewallPolicy:RegionNetworkFirewallPolicy", 1)
	tracker.RequireType(t, "gcp:compute/regionNetworkFirewallPolicyAssociation:RegionNetworkFirewallPolicyAssociation", 1)
	tracker.RequireType(t, "gcp:compute/regionNetworkFirewallPolicyRule:RegionNetworkFirewallPolicyRule", 5)
}

func TestNewNetworkFirewallPolicy_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewNetworkFirewallPolicy(ctx, "test", nil)
		require.Error(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", testutil.NewTracker()))
	require.NoError(t, err)
}
