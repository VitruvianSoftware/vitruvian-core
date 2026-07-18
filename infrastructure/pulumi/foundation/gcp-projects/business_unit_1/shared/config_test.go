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
// workspace), the API-propagation knob defaults to 120s, and the org reference
// defaults to the live upstream-layout stack.
func TestLoadSharedConfigDefaults(t *testing.T) {
	// config.New(ctx, "") namespaces on the project name, which WithMocks sets to
	// "project" — so test config keys use the "project:" prefix (as in the sibling
	// foundation stacks' config tests), not the live "foundation-projects-bu1-shared:" prefix.
	os.Setenv("PULUMI_CONFIG", `{ "project:business_code": "bu1", "project:billing_account": "AAAAAA-BBBBBB-CCCCCC" }`)
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

		// Org reference defaults to the live upstream-layout stack
		assert.Equal(t, "ipv1337/foundation-org-shared/production", cfg.OrgStackName)

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
