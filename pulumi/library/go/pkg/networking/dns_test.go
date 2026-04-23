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

func TestNewDnsZone(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		// Test forwarding zone
		_, err := NewDnsZone(ctx, "test-fwd-zone", &DnsZoneArgs{
			ProjectID:                 pulumi.String("test-proj"),
			Name:                      "test-fwd",
			Domain:                    "fwd.example.com.",
			Type:                      "forwarding",
			NetworkSelfLink:           pulumi.String("vpc-link"),
			TargetNameServerAddresses: []string{"10.0.0.1"},
			ForwardingPath:            "default",
			Description:               "Forwarding zone",
			Labels:                    map[string]string{"env": "test"},
		})
		require.NoError(t, err)

		// Test private zone with recordsets
		_, err = NewDnsZone(ctx, "test-priv-zone", &DnsZoneArgs{
			ProjectID:       pulumi.String("test-proj"),
			Name:            "test-priv",
			Domain:          "priv.example.com.",
			Type:            "private",
			NetworkSelfLink: pulumi.String("vpc-link"),
			Recordsets: []RecordSet{
				{Type: "A", TTL: 300, Records: []string{"10.0.0.2"}, Name: "test"},
			},
		})
		require.NoError(t, err)

		// Test peering zone
		_, err = NewDnsZone(ctx, "test-peer-zone", &DnsZoneArgs{
			ProjectID:             pulumi.String("test-proj"),
			Name:                  "test-peer",
			Domain:                "peer.example.com.",
			Type:                  "peering",
			NetworkSelfLink:       pulumi.String("vpc-link"),
			TargetNetworkSelfLink: pulumi.String("peer-vpc-link"),
		})
		require.NoError(t, err)

		// Test public zone
		_, err = NewDnsZone(ctx, "test-pub-zone", &DnsZoneArgs{
			ProjectID:    pulumi.String("test-proj"),
			Name:         "test-pub",
			Domain:       "example.com.",
			Type:         "public",
			EnableDnssec: true,
			DnssecState:  "on",
		})
		require.NoError(t, err)

		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:dns/managedZone:ManagedZone", 4)
	tracker.RequireType(t, "gcp:dns/recordSet:RecordSet", 1)
}

func TestNewDnsZone_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewDnsZone(ctx, "test", nil)
		require.Error(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", testutil.NewTracker()))
	require.NoError(t, err)
}
