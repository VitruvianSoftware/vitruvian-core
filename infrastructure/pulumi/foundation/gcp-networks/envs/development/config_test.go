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

func TestPinnedEnvIdentity(t *testing.T) {
	// The environment identity and spoke CIDR plan are pinned by this leaf
	// project, mirroring upstream 3-networks-hub-and-spoke/envs/development.
	assert.Equal(t, "development", pinnedEnv)
	assert.Equal(t, "d", pinnedEnvCode)

	// Spoke CIDRs must not overlap the hub (10.8.0.0/18, 10.9.0.0/18) or the
	// other environments (see the sibling leaves).
	assert.Equal(t, "10.8.64.0/18", spokeSubnet1Cidr)
	assert.Equal(t, "10.9.64.0/18", spokeSubnet2Cidr)
	assert.Equal(t, "10.26.2.0/23", spokeProxy1Cidr)
	assert.Equal(t, "10.27.2.0/23", spokeProxy2Cidr)

	// Secondary ranges only on R1 (matching upstream)
	assert.Equal(t, "100.72.64.0/18", spokeGkePod1Cidr)
	assert.Equal(t, "100.73.64.0/18", spokeGkeSvc1Cidr)
}

func TestLoadNetConfig(t *testing.T) {
	os.Setenv("PULUMI_CONFIG", `{"project:org_id":"123"}`)
	defer os.Unsetenv("PULUMI_CONFIG")

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cfg := loadNetConfig(ctx)

		// Verify defaults
		// Region defaults are pinned to the canonical bootstrap regions
		// (common_config.default_region / default_region_2). If a config drift
		// makes this fail, fix the config back to bootstrap — do NOT relax the
		// assertion (that is how the secondary silently became us-south1).
		assert.Equal(t, "us-central1", cfg.Region1)
		assert.Equal(t, "us-west1", cfg.Region2)
		assert.Equal(t, "ipv1337/foundation-org-shared/production", cfg.OrgStackName)
		assert.Equal(t, 2, cfg.NatNumAddresses)
		assert.True(t, cfg.FirewallPoliciesEnableLogging)
		assert.True(t, cfg.DnsEnableLogging)
		assert.False(t, cfg.EnforceVpcSc) // Dry-run first

		// Verify feature toggle defaults (all false matching upstream)
		assert.False(t, cfg.NatEnabled)
		assert.False(t, cfg.WindowsActivationEnabled)
		return nil
	}, pulumi.WithMocks("project", "stack", mocks(0)))
	assert.NoError(t, err)
}
