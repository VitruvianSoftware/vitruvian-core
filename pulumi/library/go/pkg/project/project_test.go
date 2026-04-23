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

package project

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// gcpProject is the Pulumi type token for the GCP project child resource.
const gcpProject = "gcp:organizations/project:Project"

// gcpService is the Pulumi type token for the GCP project service child resource.
const gcpService = "gcp:projects/service:Service"

// randomID is the Pulumi type token for the random ID child resource.
const randomID = "random:index/randomId:RandomId"

// ---------- Basic Creation ----------

func TestNewProject_Basic(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		p, err := NewProject(ctx, "test-proj", &ProjectArgs{
			ProjectID:      pulumi.String("prj-test"),
			Name:           pulumi.String("Test Project"),
			FolderID:       pulumi.String("folders/123"),
			BillingAccount: pulumi.String("AAAAAA-BBBBBB-CCCCCC"),
			Budget: &BudgetConfig{
				Amount: 200,
			},
			Lien:                  true,
			DefaultServiceAccount: "DISABLE",
			ActivateApis:          []string{"compute.googleapis.com"},
		})
		require.NoError(t, err)
		assert.NotNil(t, p)
		assert.NotNil(t, p.Project)
		assert.NotEmpty(t, p.Services, "APIs specified → services exist")
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	projects := tracker.RequireType(t, gcpProject, 1)
	assert.Equal(t, "Test Project", projects[0].Inputs["name"].StringValue())
	assert.Equal(t, "prj-test", projects[0].Inputs["projectId"].StringValue())
	assert.Equal(t, "folders/123", projects[0].Inputs["folderId"].StringValue())
	assert.Equal(t, "AAAAAA-BBBBBB-CCCCCC", projects[0].Inputs["billingAccount"].StringValue())

	tracker.RequireType(t, "gcp:billing/budget:Budget", 1)
	tracker.RequireType(t, "gcp:resourcemanager/lien:Lien", 1)
	tracker.RequireType(t, "gcp:projects/defaultServiceAccounts:DefaultServiceAccounts", 1)
	tracker.RequireType(t, "gcp:projects/service:Service", 1)
}

// ---------- AutoCreateNetwork ----------

func TestNewProject_AutoCreateNetworkDefaultsFalse(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewProject(ctx, "test-acn", &ProjectArgs{
			ProjectID:      pulumi.String("prj-acn"),
			Name:           pulumi.String("ACN Test"),
			FolderID:       pulumi.String("folders/456"),
			BillingAccount: pulumi.String("AAAAAA-BBBBBB-CCCCCC"),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	projects := tracker.RequireType(t, gcpProject, 1)
	assert.False(t, projects[0].Inputs["autoCreateNetwork"].BoolValue(),
		"autoCreateNetwork should default to false")
}

func TestNewProject_AutoCreateNetworkExplicitTrue(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewProject(ctx, "test-acn-true", &ProjectArgs{
			ProjectID:         pulumi.String("prj-acn-true"),
			Name:              pulumi.String("ACN True"),
			FolderID:          pulumi.String("folders/789"),
			BillingAccount:    pulumi.String("AAAAAA-BBBBBB-CCCCCC"),
			AutoCreateNetwork: pulumi.Bool(true),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	projects := tracker.RequireType(t, gcpProject, 1)
	assert.True(t, projects[0].Inputs["autoCreateNetwork"].BoolValue())
}

// ---------- Full Budget ----------

func TestNewProject_FullBudget(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewProject(ctx, "test-budget", &ProjectArgs{
			ProjectID:      pulumi.String("prj-budget"),
			Name:           pulumi.String("Budget"),
			BillingAccount: pulumi.String("AAAAAA-BBBBBB-CCCCCC"),
			Budget: &BudgetConfig{
				Amount:             100,
				AlertSpentPercents: []float64{0.8},
				AlertSpendBasis:    "FORECASTED_SPEND",
				AlertPubSubTopic:   "projects/my-proj/topics/my-topic",
			},
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:billing/budget:Budget", 1)
}

// ---------- API Activation ----------

func TestNewProject_WithAPIs(t *testing.T) {
	apis := []string{
		"bigquery.googleapis.com",
		"storage.googleapis.com",
		"cloudkms.googleapis.com",
	}
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		p, err := NewProject(ctx, "test-apis", &ProjectArgs{
			ProjectID:      pulumi.String("prj-apis"),
			Name:           pulumi.String("APIs Test"),
			FolderID:       pulumi.String("folders/111"),
			BillingAccount: pulumi.String("AAAAAA-BBBBBB-CCCCCC"),
			ActivateApis:   apis,
		})
		require.NoError(t, err)
		assert.Len(t, p.Services, 3)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	services := tracker.RequireType(t, gcpService, 3)
	registeredAPIs := map[string]bool{}
	for _, svc := range services {
		registeredAPIs[svc.Inputs["service"].StringValue()] = true
	}
	for _, api := range apis {
		assert.True(t, registeredAPIs[api], "API %q should be registered", api)
	}
}

func TestNewProject_APIsDisableOnDestroyIsFalse(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewProject(ctx, "test-disable", &ProjectArgs{
			ProjectID:      pulumi.String("prj-destroy"),
			Name:           pulumi.String("Destroy Check"),
			FolderID:       pulumi.String("folders/666"),
			BillingAccount: pulumi.String("AAAAAA-BBBBBB-CCCCCC"),
			ActivateApis:   []string{"compute.googleapis.com"},
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	services := tracker.RequireType(t, gcpService, 1)
	assert.False(t, services[0].Inputs["disableOnDestroy"].BoolValue())
	assert.False(t, services[0].Inputs["disableDependentServices"].BoolValue())
}

func TestNewProject_EmptyAPIList(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		p, err := NewProject(ctx, "test-empty-apis", &ProjectArgs{
			ProjectID:      pulumi.String("prj-empty"),
			Name:           pulumi.String("Empty APIs"),
			FolderID:       pulumi.String("folders/777"),
			BillingAccount: pulumi.String("AAAAAA-BBBBBB-CCCCCC"),
			ActivateApis:   []string{},
		})
		require.NoError(t, err)
		assert.Empty(t, p.Services)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	assert.Equal(t, 0, tracker.TypeCount(gcpService))
}

// ---------- Random Project ID ----------

func TestNewProject_RandomProjectID(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		p, err := NewProject(ctx, "test-random", &ProjectArgs{
			ProjectID:       pulumi.String("prj-b-seed"),
			Name:            pulumi.String("Seed Project"),
			FolderID:        pulumi.String("folders/222"),
			BillingAccount:  pulumi.String("AAAAAA-BBBBBB-CCCCCC"),
			RandomProjectID: true,
		})
		require.NoError(t, err)
		assert.NotNil(t, p.Project)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	randomIDs := tracker.RequireType(t, randomID, 1)
	assert.Equal(t, "test-random-suffix", randomIDs[0].Name)
	assert.Equal(t, 2.0, randomIDs[0].Inputs["byteLength"].NumberValue())
}

func TestNewProject_NoRandomProjectID(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewProject(ctx, "test-no-random", &ProjectArgs{
			ProjectID:      pulumi.String("prj-static"),
			Name:           pulumi.String("Static"),
			FolderID:       pulumi.String("folders/333"),
			BillingAccount: pulumi.String("AAAAAA-BBBBBB-CCCCCC"),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	assert.Equal(t, 0, tracker.TypeCount(randomID))
}

func TestNewProject_RandomProjectIDWithAPIs(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		p, err := NewProject(ctx, "test-random-apis", &ProjectArgs{
			ProjectID:       pulumi.String("prj-b-seed"),
			Name:            pulumi.String("Seed with APIs"),
			FolderID:        pulumi.String("folders/888"),
			BillingAccount:  pulumi.String("AAAAAA-BBBBBB-CCCCCC"),
			RandomProjectID: true,
			ActivateApis:    []string{"compute.googleapis.com", "iam.googleapis.com"},
		})
		require.NoError(t, err)
		assert.Len(t, p.Services, 2)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, randomID, 1)
	tracker.RequireType(t, gcpService, 2)
}

// ---------- Labels & Deletion Policy ----------

func TestNewProject_DeletionPolicy(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewProject(ctx, "test-delete", &ProjectArgs{
			ProjectID:      pulumi.String("prj-delete"),
			Name:           pulumi.String("Delete Test"),
			FolderID:       pulumi.String("folders/444"),
			BillingAccount: pulumi.String("AAAAAA-BBBBBB-CCCCCC"),
			DeletionPolicy: pulumi.String("DELETE"),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	projects := tracker.RequireType(t, gcpProject, 1)
	assert.Equal(t, "DELETE", projects[0].Inputs["deletionPolicy"].StringValue())
}

func TestNewProject_NoDeletionPolicy(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewProject(ctx, "test-no-dp", &ProjectArgs{
			ProjectID:      pulumi.String("prj-no-dp"),
			Name:           pulumi.String("No DP"),
			FolderID:       pulumi.String("folders/999"),
			BillingAccount: pulumi.String("AAAAAA-BBBBBB-CCCCCC"),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	projects := tracker.RequireType(t, gcpProject, 1)
	dp := projects[0].Inputs["deletionPolicy"]
	assert.True(t, dp.IsNull(), "deletionPolicy should not be set when unspecified")
}

func TestNewProject_Labels(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewProject(ctx, "test-labels", &ProjectArgs{
			ProjectID:      pulumi.String("prj-labels"),
			Name:           pulumi.String("Labels Test"),
			FolderID:       pulumi.String("folders/555"),
			BillingAccount: pulumi.String("AAAAAA-BBBBBB-CCCCCC"),
			Labels: pulumi.StringMap{
				"environment": pulumi.String("dev"),
				"team":        pulumi.String("platform"),
			},
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	projects := tracker.RequireType(t, gcpProject, 1)
	labels := projects[0].Inputs["labels"]
	assert.True(t, labels.IsObject())
	assert.Equal(t, "dev", labels.ObjectValue()["environment"].StringValue())
	assert.Equal(t, "platform", labels.ObjectValue()["team"].StringValue())
}

// ---------- Service naming convention ----------

func TestNewProject_ServiceResourceNaming(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewProject(ctx, "my-proj", &ProjectArgs{
			ProjectID:      pulumi.String("prj-naming"),
			Name:           pulumi.String("Naming Test"),
			FolderID:       pulumi.String("folders/100"),
			BillingAccount: pulumi.String("AAAAAA-BBBBBB-CCCCCC"),
			ActivateApis:   []string{"compute.googleapis.com"},
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	// Service resources should be named "{component}-{api}"
	svc := tracker.ByName("my-proj-compute.googleapis.com")
	require.NotNil(t, svc, "service resource should follow naming convention")
	assert.Equal(t, "compute.googleapis.com", svc.Inputs["service"].StringValue())
}

// ---------- Budget ----------

const gcpBudget = "gcp:billing/budget:Budget"

func TestNewProject_WithBudget(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewProject(ctx, "test-budget", &ProjectArgs{
			ProjectID:      pulumi.String("prj-budget"),
			Name:           pulumi.String("Budget Test"),
			FolderID:       pulumi.String("folders/100"),
			BillingAccount: pulumi.String("AAAAAA-BBBBBB-CCCCCC"),
			Budget: &BudgetConfig{
				Amount:             1000,
				AlertSpentPercents: []float64{0.5, 0.9, 1.2},
			},
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	budgets := tracker.RequireType(t, gcpBudget, 1)
	assert.Equal(t, "AAAAAA-BBBBBB-CCCCCC", budgets[0].Inputs["billingAccount"].StringValue())
}

func TestNewProject_NoBudget(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewProject(ctx, "test-no-budget", &ProjectArgs{
			ProjectID:      pulumi.String("prj-no-budget"),
			Name:           pulumi.String("No Budget"),
			FolderID:       pulumi.String("folders/200"),
			BillingAccount: pulumi.String("AAAAAA-BBBBBB-CCCCCC"),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	assert.Equal(t, 0, tracker.TypeCount(gcpBudget))
}

// ---------- Default Service Account ----------

const gcpDefaultSA = "gcp:projects/defaultServiceAccounts:DefaultServiceAccounts"

func TestNewProject_DefaultServiceAccountDisable(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewProject(ctx, "test-dsa", &ProjectArgs{
			ProjectID:             pulumi.String("prj-dsa"),
			Name:                  pulumi.String("DSA Test"),
			FolderID:              pulumi.String("folders/300"),
			BillingAccount:        pulumi.String("AAAAAA-BBBBBB-CCCCCC"),
			DefaultServiceAccount: "disable",
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	dsas := tracker.RequireType(t, gcpDefaultSA, 1)
	assert.Equal(t, "DISABLE", dsas[0].Inputs["action"].StringValue())
}

func TestNewProject_DefaultServiceAccountKeep(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewProject(ctx, "test-dsa-keep", &ProjectArgs{
			ProjectID:             pulumi.String("prj-dsa-keep"),
			Name:                  pulumi.String("DSA Keep"),
			FolderID:              pulumi.String("folders/400"),
			BillingAccount:        pulumi.String("AAAAAA-BBBBBB-CCCCCC"),
			DefaultServiceAccount: "keep",
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	assert.Equal(t, 0, tracker.TypeCount(gcpDefaultSA),
		"keep should not create a DefaultServiceAccounts resource")
}

// ---------- Lien ----------

const gcpLien = "gcp:resourcemanager/lien:Lien"

func TestNewProject_WithLien(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewProject(ctx, "test-lien", &ProjectArgs{
			ProjectID:      pulumi.String("prj-lien"),
			Name:           pulumi.String("Lien Test"),
			FolderID:       pulumi.String("folders/500"),
			BillingAccount: pulumi.String("AAAAAA-BBBBBB-CCCCCC"),
			Lien:           true,
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	liens := tracker.RequireType(t, gcpLien, 1)
	assert.Equal(t, "project-factory", liens[0].Inputs["origin"].StringValue())
}

func TestNewProject_NoLien(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewProject(ctx, "test-no-lien", &ProjectArgs{
			ProjectID:      pulumi.String("prj-no-lien"),
			Name:           pulumi.String("No Lien"),
			FolderID:       pulumi.String("folders/600"),
			BillingAccount: pulumi.String("AAAAAA-BBBBBB-CCCCCC"),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	assert.Equal(t, 0, tracker.TypeCount(gcpLien))
}
