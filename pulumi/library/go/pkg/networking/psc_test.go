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

func TestNewPrivateServiceConnect(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewPrivateServiceConnect(ctx, "test-psc", &PrivateServiceConnectArgs{
			ProjectID:                 pulumi.String("test-proj"),
			NetworkSelfLink:           pulumi.String("vpc-link"),
			ForwardingRuleTarget:      "vpc-sc",
			IPAddress:                 "10.0.0.5",
			PscGlobalAccess:           true,
			ServiceDirectoryNamespace: "test-ns",
			ServiceDirectoryRegion:    "us-central1",
			DnsCode:                   "d",
		})
		require.NoError(t, err)

		// Test all-apis and no service directory
		_, err = NewPrivateServiceConnect(ctx, "test-psc-all", &PrivateServiceConnectArgs{
			ProjectID:            pulumi.String("test-proj"),
			NetworkSelfLink:      pulumi.String("vpc-link"),
			ForwardingRuleTarget: "all-apis",
			IPAddress:            "10.0.0.6",
			PscGlobalAccess:      false,
			DnsCode:              "d",
		})
		require.NoError(t, err)

		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:compute/globalAddress:GlobalAddress", 2)
	tracker.RequireType(t, "gcp:compute/globalForwardingRule:GlobalForwardingRule", 2)
	tracker.RequireType(t, "gcp:dns/managedZone:ManagedZone", 6)
	tracker.RequireType(t, "gcp:dns/recordSet:RecordSet", 12)
}

func TestNewTransitivityAppliance(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewTransitivityAppliance(ctx, "test-trans", &TransitivityApplianceArgs{
			ProjectID:   pulumi.String("test-proj"),
			Regions:     []string{"us-central1"},
			Network:     pulumi.String("vpc-link"),
			NetworkName: "test-vpc",
			Subnetworks: map[string]pulumi.StringInput{"us-central1": pulumi.String("sub-link")},
			RegionalAggregates: map[string][]string{
				"us-central1": {"10.0.0.0/8"},
			},
			FirewallPolicy: pulumi.String("fw-policy"),
			TargetSize:     1,
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:serviceaccount/account:Account", 1)
	tracker.RequireType(t, "gcp:projects/iAMMember:IAMMember", 2)
	tracker.RequireType(t, "gcp:compute/healthCheck:HealthCheck", 1)
	tracker.RequireType(t, "gcp:compute/instanceTemplate:InstanceTemplate", 1)
	tracker.RequireType(t, "gcp:compute/regionInstanceGroupManager:RegionInstanceGroupManager", 1)
	tracker.RequireType(t, "gcp:compute/regionBackendService:RegionBackendService", 1)
	tracker.RequireType(t, "gcp:compute/forwardingRule:ForwardingRule", 1)
	tracker.RequireType(t, "gcp:compute/route:Route", 1)
}

func TestNewPrivateServiceConnect_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewPrivateServiceConnect(ctx, "test", nil)
		require.Error(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", testutil.NewTracker()))
	require.NoError(t, err)
}

func TestNewTransitivityAppliance_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewTransitivityAppliance(ctx, "test", nil)
		require.Error(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", testutil.NewTracker()))
	require.NoError(t, err)
}
