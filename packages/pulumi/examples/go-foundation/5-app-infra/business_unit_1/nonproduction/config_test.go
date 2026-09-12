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

// TestAppConfigDefaults verifies the loader's default posture — most
// importantly that the environment identity is PINNED by this leaf (not read
// from config), that the 4-projects env-leaf reference defaults to this
// environment's business_unit_1/<env> leaf, and that the shared reference
// derives from it by name substitution.
func TestAppConfigDefaults(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cfg := loadAppInfraConfig(ctx)

		// Environment identity is pinned by the leaf, not configurable.
		assert.Equal(t, pinnedEnv, cfg.Env)
		assert.Equal(t, pinnedEnvCode, cfg.EnvCode)
		assert.Equal(t, "bu1", cfg.BusinessCode)

		// Cross-stage references default to the Phase-5 4-projects leaf stacks;
		// the shared reference derives from the env reference by substitution.
		assert.Equal(t,
			"organization/vitruvian/foundation-projects-bu1-"+pinnedEnv+"/production",
			cfg.ProjectsStackName)
		assert.Equal(t,
			"organization/vitruvian/foundation-projects-bu1-shared/production",
			cfg.ProjectsSharedStackName)

		// Serverless workload is opt-in: no image digest configured by default,
		// so the reference stack applies without a build.
		assert.Empty(t, cfg.ServerlessImageDigest)

		return nil
	}, pulumi.WithMocks("project", "stack", mocks(0)))
	assert.NoError(t, err)
}
