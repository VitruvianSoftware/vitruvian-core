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
	"os"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
)

type sharedMocks int

func (sharedMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	return args.Name + "_id", args.Inputs, nil
}

func (sharedMocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

// TestLoadSharedConfigDefaults verifies the shared leaf's default posture:
// the common identity is pinned (common/c), the infra-pipeline toggle defaults
// to true (this leaf exists to deploy it, mirroring upstream's shared
// workspace), and the API-propagation knob defaults to 120s.
func TestLoadSharedConfigDefaults(t *testing.T) {
	// config.New(ctx, "") namespaces on the project name, which WithMocks sets to
	// "project" — so test config keys use the "project:" prefix (as in the sibling
	// foundation stacks' config tests), not the "foundation-projects-bu1-shared:" stack prefix.
	os.Setenv("PULUMI_CONFIG", `{ "project:business_code": "bu1", "project:billing_account": "AAAAAA-BBBBBB-CCCCCC", "project:org_stack_name": "organization/vitruvian/foundation-org-shared/production" }`)
	defer os.Unsetenv("PULUMI_CONFIG")

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cfg := loadSharedConfig(ctx)

		// Common identity is pinned by the leaf, not configurable.
		assert.Equal(t, "common", cfg.Env)
		assert.Equal(t, "c", cfg.EnvCode)
		assert.Equal(t, "bu1", cfg.BusinessCode)
		assert.Equal(t, "prj", cfg.ProjectPrefix)

		// The pipeline is deployed by default (upstream enable_cloudbuild_deploy
		// analogue on the shared workspace).
		assert.True(t, cfg.InfraPipelineEnabled)

		// API propagation wait defaults to 120s (cold-deploy race hardening)
		assert.Equal(t, 120, cfg.ApiPropagationSeconds)

		assert.True(t, cfg.RandomSuffix)
		assert.Equal(t, "us-central1", cfg.Region)

		// Required org reference round-trips
		assert.Equal(t, "organization/vitruvian/foundation-org-shared/production", cfg.OrgStackName)

		return nil
	}, pulumi.WithMocks("project", "stack", sharedMocks(0)))

	assert.NoError(t, err)
}

// TestBudgetConfig validates budget configuration creation.
func TestBudgetConfig(t *testing.T) {
	cfg := &SharedConfig{
		BudgetAmount: 1000.0,
	}
	bc := budgetConfig(cfg)
	assert.NotNil(t, bc)
	assert.Equal(t, float64(1000), bc.Amount)
}

// TestCommonProjectLabels asserts the COMMON-folder label set used by the
// shared infra-pipeline project: upstream labels it environment=common/
// env_code=c with a RAW application_name, not a per-env identity.
func TestCommonProjectLabels(t *testing.T) {
	cfg := &SharedConfig{
		Env:              pinnedEnv,
		EnvCode:          pinnedEnvCode,
		BusinessCode:     "bu1",
		BillingCode:      "1234",
		PrimaryContact:   "james@example.com",
		SecondaryContact: "kim@example.com",
	}
	l := commonProjectLabels(cfg, "app-infra-pipelines")

	assert.Equal(t, pulumi.String("common"), l["environment"], "common-folder → environment=common")
	assert.Equal(t, pulumi.String("c"), l["env_code"], "common-folder → env_code=c")
	assert.Equal(t, pulumi.String("app-infra-pipelines"), l["application_name"], "raw application_name, not BU-prefixed")
	assert.Equal(t, pulumi.String("bu1"), l["business_code"])
	assert.Equal(t, pulumi.String("james"), l["primary_contact"])
	assert.Equal(t, pulumi.String("none"), l["vpc"])
	assert.Len(t, l, 8, "exactly 8 labels expected (matching upstream)")
}
