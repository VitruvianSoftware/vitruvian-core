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

package network_firewall_policy

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/require"
)

func TestNewNetworkFirewallPolicy_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewNetworkFirewallPolicy(ctx, "test", nil)
		require.Error(t, err)
		require.Contains(t, err.Error(), "args is required")
		return nil
	}, pulumi.WithMocks("project", "stack", testutil.NewTracker()))
	require.NoError(t, err)
}

func TestNewNetworkFirewallPolicy_Basic(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewNetworkFirewallPolicy(ctx, "test-policy", &NetworkFirewallPolicyArgs{
			Project: pulumi.String("test-proj"),
			Name:    "test-fw-policy",
			Network: pulumi.String("projects/test/global/networks/vpc"),
			Rules: []FirewallRule{
				{
					RuleName:  "allow-internal",
					Direction: "INGRESS",
					Action:    "allow",
					Priority:  1000,
					Ranges:    []string{"10.0.0.0/8"},
					Layer4Configs: []Layer4Config{
						{IpProtocol: "tcp", Ports: []string{"80", "443"}},
					},
					EnableLogging: true,
				},
			},
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:compute/networkFirewallPolicy:NetworkFirewallPolicy", 1)
	tracker.RequireType(t, "gcp:compute/networkFirewallPolicyAssociation:NetworkFirewallPolicyAssociation", 1)
	tracker.RequireType(t, "gcp:compute/networkFirewallPolicyRule:NetworkFirewallPolicyRule", 1)
}

func TestNewNetworkFirewallPolicy_MultipleRules(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewNetworkFirewallPolicy(ctx, "test-multi", &NetworkFirewallPolicyArgs{
			Project:     pulumi.String("test-proj"),
			Name:        "multi-policy",
			Description: "Multi-rule policy",
			Network:     pulumi.String("projects/test/global/networks/vpc"),
			Rules: []FirewallRule{
				{
					RuleName:  "allow-ssh",
					Direction: "INGRESS",
					Action:    "allow",
					Priority:  100,
					Ranges:    []string{"35.235.240.0/20"},
					Layer4Configs: []Layer4Config{
						{IpProtocol: "tcp", Ports: []string{"22"}},
					},
				},
				{
					RuleName:  "deny-egress",
					Direction: "EGRESS",
					Action:    "deny",
					Priority:  65534,
					Ranges:    []string{"0.0.0.0/0"},
					Layer4Configs: []Layer4Config{
						{IpProtocol: "all"},
					},
				},
			},
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:compute/networkFirewallPolicyRule:NetworkFirewallPolicyRule", 2)
}

func TestNewNetworkFirewallPolicy_WithSecureTags(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewNetworkFirewallPolicy(ctx, "test-tags", &NetworkFirewallPolicyArgs{
			Project: pulumi.String("test-proj"),
			Name:    "tags-policy",
			Network: pulumi.String("projects/test/global/networks/vpc"),
			Rules: []FirewallRule{
				{
					RuleName:  "allow-tagged",
					Direction: "INGRESS",
					Action:    "allow",
					Priority:  500,
					Ranges:    []string{"10.0.0.0/8"},
					TargetSecureTags: []SecureTag{
						{Name: "tagValues/123456"},
					},
					TargetServiceAccounts: []string{"sa@test.iam.gserviceaccount.com"},
					Layer4Configs: []Layer4Config{
						{IpProtocol: "tcp"},
					},
				},
			},
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:compute/networkFirewallPolicyRule:NetworkFirewallPolicyRule", 1)
}
