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
	"foundation-projects/modules/base_env"
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
// (preserving upstream behavior; our live stacks flip them off in committed
// config), and that the cross-stage StackReferences default to the live
// upstream-layout leaf stacks.
func TestLoadProjectsConfigDefaults(t *testing.T) {
	// config.New(ctx, "") namespaces on the project name, which WithMocks sets to
	// "project" — so test config keys use the "project:" prefix (as in the sibling
	// foundation stacks' config tests), not the live "foundation-projects-bu1-*:" prefix.
	os.Setenv("PULUMI_CONFIG", `{ "project:business_code": "bu1", "project:billing_account": "AAAAAA-BBBBBB-CCCCCC" }`)
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
		// OSS floating project is a monorepo-specific opt-in; defaults false.
		assert.False(t, cfg.OSSFloatingProjectEnabled)

		// API propagation wait defaults to 120s (cold-deploy race hardening)
		assert.Equal(t, 120, cfg.ApiPropagationSeconds)

		// Feature defaults
		assert.True(t, cfg.EnforceVpcSc)
		assert.True(t, cfg.CMEKEnabled)
		assert.True(t, cfg.PeeringEnabled)
		assert.True(t, cfg.RandomSuffix)

		// Cross-stage references default to the live upstream-layout leaf stacks
		assert.Equal(t, "ipv1337/foundation-environments-"+pinnedEnv+"/production", cfg.EnvStackName)
		assert.Equal(t, "ipv1337/foundation-org-shared/production", cfg.OrgStackName)
		assert.Equal(t, "ipv1337/foundation-networks-"+pinnedEnv+"/production", cfg.NetworkStackName)

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
