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

func TestNewNetworkPeering_DefaultNames(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewNetworkPeering(ctx, "np", &NetworkPeeringArgs{
			LocalNetwork: pulumi.String("projects/a/global/networks/vpc-a"),
			PeerNetwork:  pulumi.String("projects/b/global/networks/vpc-b"),
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	// Absent explicit names, the GCP resource names default to <name>-local / <name>-peer.
	tracker.AssertInputEquals(t, "np-local", "name", "np-local")
	tracker.AssertInputEquals(t, "np-peer", "name", "np-peer")
}

func TestNewNetworkPeering_ExplicitNames(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewNetworkPeering(ctx, "np-spoke-hub", &NetworkPeeringArgs{
			LocalNetwork:       pulumi.String("projects/a/global/networks/vpc-a"),
			PeerNetwork:        pulumi.String("projects/b/global/networks/vpc-b"),
			ImportCustomRoutes: true,
			LocalName:          "np-d-svpc-spoke-vpc-c-svpc-hub",
			PeerName:           "np-vpc-c-svpc-hub-d-svpc-spoke",
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	// Explicit names flow through to the GCP resource Name, reproducing the
	// upstream "np-<local>-<peer>" naming without hand-rolling both peerings.
	tracker.AssertInputEquals(t, "np-spoke-hub-local", "name", "np-d-svpc-spoke-vpc-c-svpc-hub")
	tracker.AssertInputEquals(t, "np-spoke-hub-peer", "name", "np-vpc-c-svpc-hub-d-svpc-spoke")
	// Reciprocal route flags: local imports, peer exports.
	tracker.AssertInputBool(t, "np-spoke-hub-local", "importCustomRoutes", true)
	tracker.AssertInputBool(t, "np-spoke-hub-peer", "exportCustomRoutes", true)
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
