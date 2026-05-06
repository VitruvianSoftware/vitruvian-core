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

package network_peering

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/require"
)

func TestNewNetworkPeering_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewNetworkPeering(ctx, "test", nil)
		require.Error(t, err)
		require.Contains(t, err.Error(), "args is required")
		return nil
	}, pulumi.WithMocks("project", "stack", testutil.NewTracker()))
	require.NoError(t, err)
}

func TestNewNetworkPeering_Basic(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewNetworkPeering(ctx, "test-peering", &NetworkPeeringArgs{
			LocalNetwork:       pulumi.String("projects/a/global/networks/vpc-a"),
			PeerNetwork:        pulumi.String("projects/b/global/networks/vpc-b"),
			ExportCustomRoutes: true,
			ImportCustomRoutes: true,
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	// Two peerings: local → peer and peer → local
	tracker.RequireType(t, "gcp:compute/networkPeering:NetworkPeering", 2)
}

func TestNewNetworkPeering_WithStackType(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewNetworkPeering(ctx, "test-dual", &NetworkPeeringArgs{
			LocalNetwork:                   pulumi.String("projects/a/global/networks/vpc-a"),
			PeerNetwork:                    pulumi.String("projects/b/global/networks/vpc-b"),
			ExportSubnetRoutesWithPublicIp: true,
			ImportSubnetRoutesWithPublicIp: false,
			StackType:                      "IPV4_IPV6",
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:compute/networkPeering:NetworkPeering", 2)
}
