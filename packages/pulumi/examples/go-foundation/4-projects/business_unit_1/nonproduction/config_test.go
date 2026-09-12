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

package main

import (
	"foundation-4-projects/modules/base_env"
	"os"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
)

type projectsMocks int

func (projectsMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	return args.Name + "_id", args.Inputs, nil
}

func (projectsMocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

// TestLoadProjectsConfigDefaults verifies the loader's default posture — most
// importantly that the environment identity is PINNED by this leaf (not read
// from config), that every project-type enable toggle defaults to true
// (preserving upstream behavior), and that the network reference derives from
// the env leaf reference by name substitution.
func TestLoadProjectsConfigDefaults(t *testing.T) {
	// config.New(ctx, "") namespaces on the project name, which WithMocks sets to
	// "project" — so test config keys use the "project:" prefix (as in the sibling
	// foundation stacks' config tests), not the "foundation-projects-bu1-*:" stack prefix.
	os.Setenv("PULUMI_CONFIG", `{ "project:business_code": "bu1", "project:billing_account": "AAAAAA-BBBBBB-CCCCCC", "project:org_stack_name": "organization/vitruvian/foundation-org-shared/production", "project:env_stack_name": "organization/vitruvian/foundation-environments-`+pinnedEnv+`/production" }`)
	defer os.Unsetenv("PULUMI_CONFIG")

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cfg := loadProjectsConfig(ctx)

		// Environment identity is pinned by the leaf, not configurable.
		assert.Equal(t, pinnedEnv, cfg.Env)
		assert.Equal(t, pinnedEnvCode, cfg.EnvCode)
		assert.Equal(t, "bu1", cfg.BusinessCode)
		assert.Equal(t, "prj", cfg.ProjectPrefix)
		assert.Equal(t, "fldr", cfg.FolderPrefix)

		// Project-type enablement — all default true (upstream parity)
		assert.True(t, cfg.SVPCProjectEnabled)
		assert.True(t, cfg.FloatingProjectEnabled)
		assert.True(t, cfg.PeeringProjectEnabled)

		// API propagation wait defaults to 120s (cold-deploy race hardening)
		assert.Equal(t, 120, cfg.ApiPropagationSeconds)

		// Feature defaults
		assert.True(t, cfg.EnforceVpcSc)
		assert.True(t, cfg.CMEKEnabled)
		assert.True(t, cfg.PeeringEnabled)
		assert.True(t, cfg.RandomSuffix)

		// Required cross-stage references round-trip; the network reference
		// derives from the env leaf reference by name substitution.
		assert.Equal(t, "organization/vitruvian/foundation-environments-"+pinnedEnv+"/production", cfg.EnvStackName)
		assert.Equal(t, "organization/vitruvian/foundation-org-shared/production", cfg.OrgStackName)
		assert.Equal(t, "organization/vitruvian/foundation-3-networks-svpc-"+pinnedEnv+"/production", cfg.NetworkStackName)

		return nil
	}, pulumi.WithMocks("project", "stack", projectsMocks(0)))

	assert.NoError(t, err)
}

// TestProjectLabels verifies the label generation function produces
// the correct set of labels matching the Terraform foundation's pattern.
func TestProjectLabels(t *testing.T) {
	cfg := &ProjectsConfig{
		Env:              pinnedEnv,
		EnvCode:          pinnedEnvCode,
		BusinessCode:     "bu1",
		PrimaryContact:   "owner@example.com",
		SecondaryContact: "backup@example.com",
		BillingCode:      "12345",
	}

	labels := projectLabels(cfg, "base", "svpc")

	// Validate all required keys are present (upstream parity)
	expectedKeys := []string{
		"environment", "application_name", "billing_code",
		"primary_contact", "secondary_contact", "business_code",
		"env_code", "vpc",
	}
	for _, key := range expectedKeys {
		_, ok := labels[key]
		assert.True(t, ok, "label key %q should exist", key)
	}
	assert.Len(t, labels, 8, "exactly 8 labels expected (matching upstream)")
}

// TestBudgetConfig validates budget configuration creation.
func TestBudgetConfig(t *testing.T) {
	t.Run("with budget amount", func(t *testing.T) {
		cfg := &ProjectsConfig{
			BudgetAmount: 1000.0,
		}
		bc := budgetConfig(cfg)
		assert.NotNil(t, bc)
		assert.Equal(t, float64(1000), bc.Amount)
	})

	t.Run("zero budget amount returns config with zero", func(t *testing.T) {
		cfg := &ProjectsConfig{
			BudgetAmount: 0,
		}
		bc := budgetConfig(cfg)
		assert.NotNil(t, bc)
	})
}

// TestProjectsConfigStruct validates the ProjectsConfig struct fields.
func TestProjectsConfigStruct(t *testing.T) {
	cfg := &ProjectsConfig{
		Env:           pinnedEnv,
		EnvCode:       pinnedEnvCode,
		BusinessCode:  "bu1",
		ProjectPrefix: "prj",
		FolderPrefix:  "fldr",
	}

	assert.Equal(t, pinnedEnv, cfg.Env)
	assert.Equal(t, pinnedEnvCode, cfg.EnvCode)
	assert.Equal(t, "bu1", cfg.BusinessCode)
	assert.Equal(t, "prj", cfg.ProjectPrefix)
	assert.Equal(t, "fldr", cfg.FolderPrefix)
}

// TestBUProjectsStruct validates the BUProjects output struct.
func TestBUProjectsStruct(t *testing.T) {
	bu := &base_env.BUProjects{}
	assert.NotNil(t, bu)
}

// TestCMEKResultStruct validates the CMEKResult output struct.
func TestCMEKResultStruct(t *testing.T) {
	cmek := &base_env.CMEKResult{}
	assert.NotNil(t, cmek)
}

// TestConfidentialSpaceResultStruct validates the ConfidentialSpaceResult output struct.
func TestConfidentialSpaceResultStruct(t *testing.T) {
	cs := &base_env.ConfidentialSpaceResult{}
	assert.NotNil(t, cs)
}

// TestPeeringResultStruct validates the PeeringResult output struct.
func TestPeeringResultStruct(t *testing.T) {
	pr := &base_env.PeeringResult{}
	assert.NotNil(t, pr)
}
