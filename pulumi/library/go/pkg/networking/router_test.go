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

func TestNewCloudRouter(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCloudRouter(ctx, "test-router", &RouterArgs{
			ProjectID:        pulumi.String("test-proj"),
			Region:           "us-central1",
			Network:          pulumi.String("projects/test/global/networks/test-vpc"),
			BgpAsn:           64514,
			AdvertisedGroups: []string{"ALL_SUBNETS"},
			AdvertisedIpRanges: []AdvertisedIPRange{
				{Range: "10.0.0.0/8", Description: "Test IP Range"},
			},
			EnableNat:                   true,
			NatNumAddresses:             2,
			KeepaliveInterval:           20,
			EncryptedInterconnectRouter: true,
			Description:                 "Test Router",
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:compute/router:Router", 1)
	tracker.RequireType(t, "gcp:compute/routerNat:RouterNat", 1)
	tracker.RequireType(t, "gcp:compute/address:Address", 2)
}

func TestNewCloudRouter_NoNat(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCloudRouter(ctx, "test-router-nonat", &RouterArgs{
			ProjectID: pulumi.String("test-proj"),
			Region:    "us-central1",
			Network:   pulumi.String("projects/test/global/networks/test-vpc"),
			BgpAsn:    64514,
			EnableNat: false,
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:compute/router:Router", 1)
}

func TestNewCloudRouter_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCloudRouter(ctx, "test", nil)
		require.Error(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", testutil.NewTracker()))
	require.NoError(t, err)
}
