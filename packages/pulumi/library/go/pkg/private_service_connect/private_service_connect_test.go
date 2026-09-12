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

package private_service_connect

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/require"
)

func TestNewPrivateServiceConnect_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewPrivateServiceConnect(ctx, "test", nil)
		require.Error(t, err)
		require.Contains(t, err.Error(), "args is required")
		return nil
	}, pulumi.WithMocks("project", "stack", testutil.NewTracker()))
	require.NoError(t, err)
}

func TestNewPrivateServiceConnect_AllApis(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewPrivateServiceConnect(ctx, "test-psc", &PrivateServiceConnectArgs{
			ProjectID:            pulumi.String("test-proj"),
			NetworkSelfLink:      pulumi.String("projects/test/global/networks/vpc"),
			DnsCode:              "hub",
			IPAddress:            "10.0.0.5",
			ForwardingRuleTarget: "all-apis",
			PscGlobalAccess:      true,
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:compute/globalAddress:GlobalAddress", 1)
	tracker.RequireType(t, "gcp:compute/globalForwardingRule:GlobalForwardingRule", 1)
	// 3 DNS zones: googleapis, gcr.io, pkg.dev
	tracker.RequireType(t, "gcp:dns/managedZone:ManagedZone", 3)
	// Each zone: CNAME + A record = 6 total
	tracker.RequireType(t, "gcp:dns/recordSet:RecordSet", 6)
}

func TestNewPrivateServiceConnect_VpcSc(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewPrivateServiceConnect(ctx, "test-vpcsc", &PrivateServiceConnectArgs{
			ProjectID:            pulumi.String("test-proj"),
			NetworkSelfLink:      pulumi.String("projects/test/global/networks/vpc"),
			IPAddress:            "10.0.0.6",
			ForwardingRuleTarget: "vpc-sc",
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:compute/globalAddress:GlobalAddress", 1)
	tracker.RequireType(t, "gcp:dns/managedZone:ManagedZone", 3)
}
