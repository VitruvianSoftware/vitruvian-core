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

package cloud_router

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/require"
)

func TestNewCloudRouter_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCloudRouter(ctx, "test", nil)
		require.Error(t, err)
		require.Contains(t, err.Error(), "args is required")
		return nil
	}, pulumi.WithMocks("project", "stack", testutil.NewTracker()))
	require.NoError(t, err)
}

func TestNewCloudRouter_Basic(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCloudRouter(ctx, "test-router", &CloudRouterArgs{
			ProjectID: pulumi.String("test-proj"),
			Region:    "us-central1",
			Network:   pulumi.String("projects/test/global/networks/vpc"),
			BgpAsn:    64514,
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:compute/router:Router", 1)
	// No NAT by default
	tracker.RequireType(t, "gcp:compute/routerNat:RouterNat", 0)
}

func TestNewCloudRouter_WithNat(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCloudRouter(ctx, "test-router-nat", &CloudRouterArgs{
			ProjectID:       pulumi.String("test-proj"),
			Region:          "us-central1",
			Network:         pulumi.String("projects/test/global/networks/vpc"),
			BgpAsn:          64514,
			EnableNat:       true,
			NatNumAddresses: 2,
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:compute/router:Router", 1)
	tracker.RequireType(t, "gcp:compute/routerNat:RouterNat", 1)
	tracker.RequireType(t, "gcp:compute/address:Address", 2)
}

func TestNewCloudRouter_CustomAdvertisements(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCloudRouter(ctx, "test-router-adv", &CloudRouterArgs{
			ProjectID:        pulumi.String("test-proj"),
			Region:           "us-central1",
			Network:          pulumi.String("projects/test/global/networks/vpc"),
			BgpAsn:           64514,
			Description:      "Custom router",
			KeepaliveInterval: 20,
			AdvertisedGroups: []string{"ALL_SUBNETS"},
			AdvertisedIpRanges: []AdvertisedIPRange{
				{Range: "10.0.0.0/8", Description: "RFC1918"},
				{Range: "172.16.0.0/12", Description: "RFC1918 B"},
			},
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:compute/router:Router", 1)
}
