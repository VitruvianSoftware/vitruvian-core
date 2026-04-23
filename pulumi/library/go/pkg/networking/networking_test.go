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
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewNetworking_Basic(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		n, err := NewNetworking(ctx, "test-net", &NetworkingArgs{
			ProjectID: pulumi.String("prj-net-test"),
			VPCName:   pulumi.String("vpc-shared"),
		})
		require.NoError(t, err)
		assert.NotNil(t, n.VPC)
		assert.Empty(t, n.Subnets)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:compute/network:Network", 1)
	tracker.AssertInputBool(t, "test-net-vpc", "autoCreateSubnetworks", false)
}

func TestNewNetworking_DefaultDeleteRoutes(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewNetworking(ctx, "test-routes", &NetworkingArgs{
			ProjectID: pulumi.String("prj-routes"),
			VPCName:   pulumi.String("vpc-test"),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.AssertInputBool(t, "test-routes-vpc", "deleteDefaultRoutesOnCreate", true)
}

func TestNewNetworking_DeleteRoutesExplicitFalse(t *testing.T) {
	tracker := testutil.NewTracker()
	f := false
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewNetworking(ctx, "test-no-delete", &NetworkingArgs{
			ProjectID:                   pulumi.String("prj-no-delete"),
			VPCName:                     pulumi.String("vpc-keep-routes"),
			DeleteDefaultRoutesOnCreate: &f,
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.AssertInputBool(t, "test-no-delete-vpc", "deleteDefaultRoutesOnCreate", false)
}

func TestNewNetworking_DefaultRoutingModeGlobal(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewNetworking(ctx, "test-routing", &NetworkingArgs{
			ProjectID: pulumi.String("prj-routing"),
			VPCName:   pulumi.String("vpc-routing"),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.AssertInputEquals(t, "test-routing-vpc", "routingMode", "GLOBAL")
}

func TestNewNetworking_RegionalRoutingMode(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewNetworking(ctx, "test-regional", &NetworkingArgs{
			ProjectID:   pulumi.String("prj-regional"),
			VPCName:     pulumi.String("vpc-regional"),
			RoutingMode: "REGIONAL",
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.AssertInputEquals(t, "test-regional-vpc", "routingMode", "REGIONAL")
}

func TestNewNetworking_WithSubnets(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		n, err := NewNetworking(ctx, "test-subnets", &NetworkingArgs{
			ProjectID: pulumi.String("prj-subnets"),
			VPCName:   pulumi.String("vpc-subnets"),
			Subnets: []SubnetArgs{
				{Name: "sb-dev-us-central1", Region: "us-central1", CIDR: "10.0.0.0/24"},
				{Name: "sb-dev-us-east1", Region: "us-east1", CIDR: "10.1.0.0/24", FlowLogs: true},
			},
		})
		require.NoError(t, err)
		assert.Len(t, n.Subnets, 2)
		assert.Contains(t, n.Subnets, "sb-dev-us-central1")
		assert.Contains(t, n.Subnets, "sb-dev-us-east1")
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	subnets := tracker.RequireType(t, "gcp:compute/subnetwork:Subnetwork", 2)
	for _, s := range subnets {
		assert.True(t, s.Inputs["privateIpGoogleAccess"].BoolValue(),
			"subnet %s should have privateIpGoogleAccess", s.Name)
	}
}

func TestNewNetworking_SubnetFlowLogs(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewNetworking(ctx, "test-flowlogs", &NetworkingArgs{
			ProjectID: pulumi.String("prj-flowlogs"),
			VPCName:   pulumi.String("vpc-flowlogs"),
			Subnets:   []SubnetArgs{{Name: "sb-logs", Region: "us-central1", CIDR: "10.0.0.0/24", FlowLogs: true}},
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	subnets := tracker.RequireType(t, "gcp:compute/subnetwork:Subnetwork", 1)
	logConfig := subnets[0].Inputs["logConfig"]
	assert.True(t, logConfig.IsObject(), "logConfig should be set when FlowLogs=true")
}

func TestNewNetworking_SubnetNoFlowLogs(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewNetworking(ctx, "test-nologs", &NetworkingArgs{
			ProjectID: pulumi.String("prj-nologs"),
			VPCName:   pulumi.String("vpc-nologs"),
			Subnets:   []SubnetArgs{{Name: "sb-nologs", Region: "us-central1", CIDR: "10.0.0.0/24"}},
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	subnets := tracker.RequireType(t, "gcp:compute/subnetwork:Subnetwork", 1)
	logConfig := subnets[0].Inputs["logConfig"]
	assert.True(t, logConfig.IsNull() || !logConfig.IsObject())
}

func TestNewNetworking_SecondaryRanges(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewNetworking(ctx, "test-sec", &NetworkingArgs{
			ProjectID: pulumi.String("prj-sec"),
			VPCName:   pulumi.String("vpc-sec"),
			Subnets: []SubnetArgs{{
				Name: "sb-gke", Region: "us-central1", CIDR: "10.0.0.0/24",
				SecondaryRanges: []SecondaryRangeArgs{
					{RangeName: "pods", CIDR: "10.4.0.0/14"},
					{RangeName: "services", CIDR: "10.8.0.0/20"},
				},
			}},
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	subnets := tracker.RequireType(t, "gcp:compute/subnetwork:Subnetwork", 1)
	secRanges := subnets[0].Inputs["secondaryIpRanges"]
	assert.True(t, secRanges.IsArray())
	assert.Len(t, secRanges.ArrayValue(), 2)
}

func TestNewNetworking_NoSecondaryRanges(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewNetworking(ctx, "test-nosec", &NetworkingArgs{
			ProjectID: pulumi.String("prj-nosec"),
			VPCName:   pulumi.String("vpc-nosec"),
			Subnets:   []SubnetArgs{{Name: "sb-plain", Region: "us-east1", CIDR: "10.2.0.0/24"}},
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	subnets := tracker.RequireType(t, "gcp:compute/subnetwork:Subnetwork", 1)
	secRanges := subnets[0].Inputs["secondaryIpRanges"]
	assert.True(t, secRanges.IsNull() || !secRanges.IsArray() || len(secRanges.ArrayValue()) == 0,
		"no secondary ranges should be set")
}

func TestNewNetworking_WithPSA(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewNetworking(ctx, "test-psa", &NetworkingArgs{
			ProjectID: pulumi.String("prj-psa"),
			VPCName:   pulumi.String("vpc-psa"),
			EnablePSA: true,
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	addrs := tracker.RequireType(t, "gcp:compute/globalAddress:GlobalAddress", 1)
	assert.Equal(t, "VPC_PEERING", addrs[0].Inputs["purpose"].StringValue())
	assert.Equal(t, "INTERNAL", addrs[0].Inputs["addressType"].StringValue())
	assert.Equal(t, 16.0, addrs[0].Inputs["prefixLength"].NumberValue())

	conns := tracker.RequireType(t, "gcp:servicenetworking/connection:Connection", 1)
	assert.Equal(t, "servicenetworking.googleapis.com", conns[0].Inputs["service"].StringValue())
}

func TestNewNetworking_WithoutPSA(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewNetworking(ctx, "test-no-psa", &NetworkingArgs{
			ProjectID: pulumi.String("prj-no-psa"),
			VPCName:   pulumi.String("vpc-no-psa"),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	assert.Equal(t, 0, tracker.TypeCount("gcp:compute/globalAddress:GlobalAddress"))
	assert.Equal(t, 0, tracker.TypeCount("gcp:servicenetworking/connection:Connection"))
}

func TestNewNetworking_FullStack(t *testing.T) {
	// Integration-style test: VPC + 2 subnets + PSA — verifies the complete resource graph.
	tracker := testutil.NewTracker()
	tr := true
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		n, err := NewNetworking(ctx, "full", &NetworkingArgs{
			ProjectID:                   pulumi.String("prj-full"),
			VPCName:                     pulumi.String("vpc-full"),
			DeleteDefaultRoutesOnCreate: &tr,
			RoutingMode:                 "GLOBAL",
			EnablePSA:                   true,
			Subnets: []SubnetArgs{
				{Name: "sb-a", Region: "us-central1", CIDR: "10.0.0.0/24", FlowLogs: true,
					SecondaryRanges: []SecondaryRangeArgs{{RangeName: "pods", CIDR: "10.4.0.0/14"}}},
				{Name: "sb-b", Region: "us-east1", CIDR: "10.1.0.0/24"},
			},
		})
		require.NoError(t, err)
		assert.Len(t, n.Subnets, 2)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	// VPC + 2 subnets + 1 GlobalAddress + 1 Connection = 5 resources + 1 component
	tracker.RequireType(t, "gcp:compute/network:Network", 1)
	tracker.RequireType(t, "gcp:compute/subnetwork:Subnetwork", 2)
	tracker.RequireType(t, "gcp:compute/globalAddress:GlobalAddress", 1)
	tracker.RequireType(t, "gcp:servicenetworking/connection:Connection", 1)
}

func TestNewNetworking_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewNetworking(ctx, "test", nil)
		require.Error(t, err)
		require.Equal(t, "args is required", err.Error())
		return nil
	}, pulumi.WithMocks("project", "stack", testutil.NewTracker()))
	require.NoError(t, err)
}
