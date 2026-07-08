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

func TestLoadNetConfig(t *testing.T) {
	os.Setenv("PULUMI_CONFIG", `{"project:env":"development", "project:env_code":"d", "project:org_id":"123", "project:hub_project_id":"prj-net-hub"}`)
	defer os.Unsetenv("PULUMI_CONFIG")

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cfg := loadNetConfig(ctx)
		assert.Equal(t, "development", cfg.Env)
		assert.Equal(t, "d", cfg.EnvCode)
		assert.Equal(t, "prj-net-hub", cfg.HubProjectID)

		// Verify dev CIDRs are assigned
		assert.Equal(t, "10.8.64.0/18", cfg.SpokeSubnet1Cidr)
		assert.Equal(t, "10.9.64.0/18", cfg.SpokeSubnet2Cidr)
		assert.Equal(t, "10.26.2.0/23", cfg.SpokeProxy1Cidr)
		assert.Equal(t, "10.27.2.0/23", cfg.SpokeProxy2Cidr)

		// Verify hub CIDRs
		assert.Equal(t, "10.0.64.0/18", cfg.HubSubnet1Cidr)
		assert.Equal(t, "10.1.64.0/18", cfg.HubSubnet2Cidr)

		// Verify defaults
		assert.Equal(t, "us-central1", cfg.Region1)
		assert.Equal(t, "us-south1", cfg.Region2)
		assert.Equal(t, 64514, cfg.BgpAsn)
		assert.Equal(t, 2, cfg.NatNumAddresses)
		assert.True(t, cfg.FirewallPoliciesEnableLogging)
		assert.True(t, cfg.DnsEnableLogging)
		assert.False(t, cfg.EnforceVpcSc) // Dry-run first
		return nil
	}, pulumi.WithMocks("project", "stack", mocks(0)))
	assert.NoError(t, err)
}

func TestLoadNetConfigNonprod(t *testing.T) {
	os.Setenv("PULUMI_CONFIG", `{"project:env":"nonproduction", "project:env_code":"n", "project:org_id":"123", "project:hub_project_id":"prj-net-hub"}`)
	defer os.Unsetenv("PULUMI_CONFIG")

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cfg := loadNetConfig(ctx)
		assert.Equal(t, "nonproduction", cfg.Env)
		assert.Equal(t, "n", cfg.EnvCode)

		// Verify nonprod CIDRs don't overlap with dev
		assert.Equal(t, "10.8.128.0/18", cfg.SpokeSubnet1Cidr)
		assert.Equal(t, "10.9.128.0/18", cfg.SpokeSubnet2Cidr)
		return nil
	}, pulumi.WithMocks("project", "stack", mocks(0)))
	assert.NoError(t, err)
}

func TestLoadNetConfigProd(t *testing.T) {
	os.Setenv("PULUMI_CONFIG", `{"project:env":"production", "project:env_code":"p", "project:org_id":"123", "project:hub_project_id":"prj-net-hub"}`)
	defer os.Unsetenv("PULUMI_CONFIG")

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cfg := loadNetConfig(ctx)
		assert.Equal(t, "production", cfg.Env)
		assert.Equal(t, "p", cfg.EnvCode)

		// Verify prod CIDRs don't overlap with dev or nonprod
		assert.Equal(t, "10.8.192.0/18", cfg.SpokeSubnet1Cidr)
		assert.Equal(t, "10.9.192.0/18", cfg.SpokeSubnet2Cidr)
		return nil
	}, pulumi.WithMocks("project", "stack", mocks(0)))
	assert.NoError(t, err)
}
