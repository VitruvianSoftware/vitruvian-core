/*
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 */

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

// TestPinnedEnvIdentity validates the environment identity and spoke CIDR plan
// pinned by this leaf project, mirroring upstream
// 3-networks-hub-and-spoke/envs/development.
func TestPinnedEnvIdentity(t *testing.T) {
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

// TestLoadNetConfig validates defaults match TF upstream.
func TestLoadNetConfig(t *testing.T) {
	os.Setenv("PULUMI_CONFIG", `{"project:spoke_project_id":"prj-d-svpc"}`)
	defer os.Unsetenv("PULUMI_CONFIG")

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cfg := loadNetConfig(ctx)

		assert.Equal(t, "prj-d-svpc", cfg.SpokeProjectID)

		// Defaults
		assert.Equal(t, "us-central1", cfg.Region1)
		assert.Equal(t, "us-west1", cfg.Region2)
		assert.Equal(t, "org", cfg.OrgStackName)
		assert.True(t, cfg.FirewallPoliciesEnableLogging)
		assert.True(t, cfg.DnsEnableLogging)
		assert.False(t, cfg.EnforceVpcSc)
		assert.False(t, cfg.NatEnabled)
		assert.False(t, cfg.WindowsActivationEnabled)
		return nil
	}, pulumi.WithMocks("project", "stack", mocks(0)))
	assert.NoError(t, err)
}
