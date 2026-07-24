// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

package main

import (
	"os"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
)

type mocks int

func (mocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	return args.Name + "_id", args.Inputs, nil
}

func (mocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

func TestPinnedSharedIdentity(t *testing.T) {
	// The shared/hub identity is pinned by this leaf project, mirroring
	// upstream 3-networks-hub-and-spoke/envs/shared.
	assert.Equal(t, "shared", pinnedEnv)
	assert.Equal(t, "c", pinnedEnvCode)
}

func TestLoadNetSharedConfig(t *testing.T) {
	// Guard exercises the committed/const FALLBACK (deploy injects the real
	// bootstrap value via these env vars — see envOrConfig). Force them empty
	// so the fallback is what we assert equals the canonical bootstrap regions.
	t.Setenv("NETWORKS_DEFAULT_REGION", "")
	t.Setenv("NETWORKS_SECONDARY_REGION", "")
	os.Setenv("PULUMI_CONFIG", `{"project:org_id":"123"}`)
	defer os.Unsetenv("PULUMI_CONFIG")

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cfg := loadNetSharedConfig(ctx)

		// Verify hub CIDRs (matching upstream)
		assert.Equal(t, "10.8.0.0/18", cfg.HubSubnet1Cidr)
		assert.Equal(t, "10.9.0.0/18", cfg.HubSubnet2Cidr)

		// Verify hub proxy CIDRs
		assert.Equal(t, "10.26.0.0/23", cfg.HubProxy1Cidr)
		assert.Equal(t, "10.27.0.0/23", cfg.HubProxy2Cidr)

		// Verify defaults
		// Region defaults are pinned to the canonical bootstrap regions
		// (common_config.default_region / default_region_2). If a config drift
		// makes this fail, fix the config back to bootstrap — do NOT relax the
		// assertion (that is how the secondary silently became us-south1).
		assert.Equal(t, "us-central1", cfg.Region1)
		assert.Equal(t, "us-west1", cfg.Region2)
		assert.Equal(t, "ipv1337/foundation-org-shared/production", cfg.OrgStackName)
		assert.Equal(t, 64514, cfg.BgpAsn)
		assert.Equal(t, 2, cfg.NatNumAddresses)
		assert.True(t, cfg.FirewallPoliciesEnableLogging)
		assert.True(t, cfg.DnsEnableLogging)
		assert.False(t, cfg.EnforceVpcSc) // Dry-run first

		// Verify feature toggle defaults (all false matching upstream)
		assert.False(t, cfg.EnableHubAndSpokeTransitivity)
		assert.False(t, cfg.HubNatEnabled)
		assert.False(t, cfg.WindowsActivationEnabled)
		return nil
	}, pulumi.WithMocks("project", "stack", mocks(0)))
	assert.NoError(t, err)
}
