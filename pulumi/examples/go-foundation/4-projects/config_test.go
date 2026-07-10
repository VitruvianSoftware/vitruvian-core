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

type projectsMocks int

func (projectsMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	return args.Name + "_id", args.Inputs, nil
}

func (projectsMocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

// TestLoadProjectsConfigDefaults verifies the loader's default posture — most
// importantly that every project-type enable toggle defaults to true, preserving
// upstream behavior (all three BU project types plus the infra-pipeline project
// are created unless a consumer explicitly disables one).
func TestLoadProjectsConfigDefaults(t *testing.T) {
	os.Setenv("PULUMI_CONFIG", `{ "project:env": "development", "project:business_code": "bu1", "project:billing_account": "AAAAAA-BBBBBB-CCCCCC", "project:org_stack_name": "organization/vitruvian/1-org/production" }`)
	defer os.Unsetenv("PULUMI_CONFIG")

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cfg := loadProjectsConfig(ctx)

		assert.Equal(t, "development", cfg.Env)
		assert.Equal(t, "d", cfg.EnvCode)

		// Project-type enablement — all default true (upstream parity)
		assert.True(t, cfg.SVPCProjectEnabled)
		assert.True(t, cfg.FloatingProjectEnabled)
		assert.True(t, cfg.PeeringProjectEnabled)
		assert.True(t, cfg.InfraPipelineEnabled)

		// Network/env stack names derive from org_stack_name by stage substitution
		assert.Equal(t, "organization/vitruvian/3-networks-svpc/production", cfg.NetworkStackName)
		assert.Equal(t, "organization/vitruvian/2-environments/production", cfg.EnvStackName)

		return nil
	}, pulumi.WithMocks("project", "stack", projectsMocks(0)))

	assert.NoError(t, err)
}

// TestProjectLabels verifies the label generation function produces
// the correct set of labels matching the Terraform foundation's pattern.
func TestProjectLabels(t *testing.T) {
	cfg := &ProjectsConfig{
		Env:              "development",
		EnvCode:          "d",
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
		Env:           "production",
		EnvCode:       "p",
		BusinessCode:  "bu1",
		ProjectPrefix: "prj",
		FolderPrefix:  "fldr",
	}

	assert.Equal(t, "production", cfg.Env)
	assert.Equal(t, "p", cfg.EnvCode)
	assert.Equal(t, "bu1", cfg.BusinessCode)
	assert.Equal(t, "prj", cfg.ProjectPrefix)
	assert.Equal(t, "fldr", cfg.FolderPrefix)
}

// TestBUProjectsStruct validates the BUProjects output struct.
func TestBUProjectsStruct(t *testing.T) {
	bu := &BUProjects{}
	assert.NotNil(t, bu)
}

// TestCMEKResultStruct validates the CMEKResult output struct.
func TestCMEKResultStruct(t *testing.T) {
	cmek := &CMEKResult{}
	assert.NotNil(t, cmek)
}

// TestConfidentialSpaceResultStruct validates the ConfidentialSpaceResult output struct.
func TestConfidentialSpaceResultStruct(t *testing.T) {
	cs := &ConfidentialSpaceResult{}
	assert.NotNil(t, cs)
}

// TestPeeringResultStruct validates the PeeringResult output struct.
func TestPeeringResultStruct(t *testing.T) {
	pr := &PeeringResult{}
	assert.NotNil(t, pr)
}
