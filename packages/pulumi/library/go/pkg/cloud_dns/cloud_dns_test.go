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

package cloud_dns

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/require"
)

func TestNewDnsZone_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewDnsZone(ctx, "test", nil)
		require.Error(t, err)
		require.Contains(t, err.Error(), "args is required")
		return nil
	}, pulumi.WithMocks("project", "stack", testutil.NewTracker()))
	require.NoError(t, err)
}

func TestNewDnsZone_Private(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewDnsZone(ctx, "test-private", &DnsZoneArgs{
			ProjectID:       pulumi.String("test-proj"),
			Name:            "test-zone",
			Domain:          "example.com.",
			Type:            "private",
			NetworkSelfLink: pulumi.String("projects/test/global/networks/vpc"),
			Recordsets: []RecordSet{
				{Name: "www", Type: "A", TTL: 300, Records: []string{"10.0.0.1"}},
			},
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:dns/managedZone:ManagedZone", 1)
	tracker.RequireType(t, "gcp:dns/recordSet:RecordSet", 1)
}

func TestNewDnsZone_Forwarding(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewDnsZone(ctx, "test-fwd", &DnsZoneArgs{
			ProjectID:                 pulumi.String("test-proj"),
			Name:                      "fwd-zone",
			Domain:                    "corp.example.com.",
			Type:                      "forwarding",
			NetworkSelfLink:           pulumi.String("projects/test/global/networks/vpc"),
			TargetNameServerAddresses: []string{"10.0.0.53", "10.0.1.53"},
			ForwardingPath:            "default",
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:dns/managedZone:ManagedZone", 1)
}

func TestNewDnsZone_Peering(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewDnsZone(ctx, "test-peer", &DnsZoneArgs{
			ProjectID:             pulumi.String("test-proj"),
			Name:                  "peer-zone",
			Domain:                "peer.example.com.",
			Type:                  "peering",
			NetworkSelfLink:       pulumi.String("projects/test/global/networks/vpc"),
			TargetNetworkSelfLink: pulumi.String("projects/test/global/networks/peer-vpc"),
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:dns/managedZone:ManagedZone", 1)
}

func TestNewDnsZone_Public(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewDnsZone(ctx, "test-public", &DnsZoneArgs{
			ProjectID:    pulumi.String("test-proj"),
			Name:         "public-zone",
			Domain:       "public.example.com.",
			Type:         "public",
			EnableDnssec: true,
			Labels:       map[string]string{"env": "prod"},
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:dns/managedZone:ManagedZone", 1)
}

func TestNewDnsZone_ReverseLookup(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewDnsZone(ctx, "test-reverse", &DnsZoneArgs{
			ProjectID:       pulumi.String("test-proj"),
			Name:            "reverse-zone",
			Domain:          "10.in-addr.arpa.",
			Type:            "reverse_lookup",
			NetworkSelfLink: pulumi.String("projects/test/global/networks/vpc"),
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:dns/managedZone:ManagedZone", 1)
}

func TestNewDnsZone_DefaultDescription(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewDnsZone(ctx, "test-desc", &DnsZoneArgs{
			ProjectID: pulumi.String("test-proj"),
			Name:      "desc-zone",
			Domain:    "desc.example.com.",
			Type:      "public",
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:dns/managedZone:ManagedZone", 1)
}

func TestNewDnsZone_MultipleRecordsets(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewDnsZone(ctx, "test-multi-rs", &DnsZoneArgs{
			ProjectID:       pulumi.String("test-proj"),
			Name:            "multi-zone",
			Domain:          "multi.example.com.",
			Type:            "private",
			NetworkSelfLink: pulumi.String("projects/test/global/networks/vpc"),
			Recordsets: []RecordSet{
				{Name: "www", Type: "A", Records: []string{"10.0.0.1"}},
				{Name: "mail", Type: "MX", TTL: 600, Records: []string{"10 mail.example.com."}},
				{Name: "", Type: "A", TTL: 300, Records: []string{"10.0.0.2"}},
			},
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:dns/managedZone:ManagedZone", 1)
	tracker.RequireType(t, "gcp:dns/recordSet:RecordSet", 3)
}
