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

// TestPinnedEnvIdentity validates the environment identity pinned by this leaf
// project, mirroring upstream 3-networks-svpc/envs/production.
func TestPinnedEnvIdentity(t *testing.T) {
	assert.Equal(t, "production", pinnedEnv)
	assert.Equal(t, "p", pinnedEnvCode)
}

func TestNetConfigDefaultsReal(t *testing.T) {
	os.Setenv("PULUMI_CONFIG", `{"project:project_id":"prj-p-svpc"}`)
	defer os.Unsetenv("PULUMI_CONFIG")

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cfg := loadNetConfig(ctx)

		assert.Equal(t, "prj-p-svpc", cfg.ProjectID)
		// Default values
		assert.Equal(t, "us-central1", cfg.Region1)
		assert.Equal(t, "us-west1", cfg.Region2)

		return nil
	}, pulumi.WithMocks("project", "stack", mocks(0)))
	assert.NoError(t, err)
}
