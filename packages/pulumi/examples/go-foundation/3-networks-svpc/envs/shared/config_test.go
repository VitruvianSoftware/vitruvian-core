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

// TestPinnedSharedIdentity validates the shared identity pinned by this leaf
// project, mirroring upstream 3-networks-svpc/envs/shared.
func TestPinnedSharedIdentity(t *testing.T) {
	assert.Equal(t, "shared", pinnedEnv)
}

func TestLoadSharedConfig(t *testing.T) {
	os.Setenv("PULUMI_CONFIG", `{"project:parent_id":"folders/123"}`)
	defer os.Unsetenv("PULUMI_CONFIG")

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cfg := loadSharedConfig(ctx)

		assert.Equal(t, "folders/123", cfg.ParentID)
		// Associations fall back to the parent; logging defaults on.
		assert.Equal(t, []string{"folders/123"}, cfg.FirewallAssociations)
		assert.True(t, cfg.FirewallPoliciesEnableLogging)
		return nil
	}, pulumi.WithMocks("project", "stack", mocks(0)))
	assert.NoError(t, err)
}
