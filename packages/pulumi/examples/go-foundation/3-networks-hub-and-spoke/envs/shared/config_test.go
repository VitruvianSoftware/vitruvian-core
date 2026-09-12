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

// TestPinnedSharedIdentity validates the shared/hub identity pinned by this
// leaf project, mirroring upstream 3-networks-hub-and-spoke/envs/shared.
func TestPinnedSharedIdentity(t *testing.T) {
	assert.Equal(t, "shared", pinnedEnv)
	assert.Equal(t, "c", pinnedEnvCode)
}

// TestLoadNetSharedConfig validates defaults match TF upstream.
func TestLoadNetSharedConfig(t *testing.T) {
	os.Setenv("PULUMI_CONFIG", `{"project:hub_project_id":"prj-c-hub-and-spoke", "project:parent_id":"organizations/123"}`)
	defer os.Unsetenv("PULUMI_CONFIG")

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cfg := loadNetSharedConfig(ctx)

		assert.Equal(t, "prj-c-hub-and-spoke", cfg.HubProjectID)

		// Hub CIDR defaults
		assert.Equal(t, "10.8.0.0/18", cfg.HubSubnet1Cidr)
		assert.Equal(t, "10.9.0.0/18", cfg.HubSubnet2Cidr)

		// Defaults
		assert.Equal(t, "us-central1", cfg.Region1)
		assert.Equal(t, "us-west1", cfg.Region2)
		assert.True(t, cfg.FirewallPoliciesEnableLogging)
		assert.True(t, cfg.DnsEnableLogging)
		assert.False(t, cfg.EnforceVpcSc)
		assert.False(t, cfg.EnableHubAndSpokeTransitivity)
		assert.False(t, cfg.HubNatEnabled)
		return nil
	}, pulumi.WithMocks("project", "stack", mocks(0)))
	assert.NoError(t, err)
}
