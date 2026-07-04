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

type mocks int

func (mocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	return args.Name + "_id", args.Inputs, nil
}

func (mocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

// TestConfigDefaults verifies that the Config struct applies the correct
// defaults matching the Terraform foundation's variables.tf defaults.
func TestConfigDefaults(t *testing.T) {
	os.Setenv("PULUMI_CONFIG", `{"project:org_id":"123456789", "project:billing_account":"000000-000000-000000", "project:group_org_admins":"org-admins@example.com", "project:group_billing_admins":"billing-admins@example.com", "project:billing_data_users":"billing-users@example.com", "project:audit_data_users":"audit-users@example.com"}`)
	defer os.Unsetenv("PULUMI_CONFIG")

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cfg := loadConfig(ctx)

		assert.Equal(t, "prj", cfg.ProjectPrefix, "project_prefix default")
		assert.Equal(t, "fldr", cfg.FolderPrefix, "folder_prefix default")
		assert.Equal(t, "bkt", cfg.BucketPrefix, "bucket_prefix default")
		assert.Equal(t, "PREVENT", cfg.ProjectDeletionPolicy, "project_deletion_policy default")
		assert.Equal(t, "us-central1", cfg.DefaultRegion, "default_region default")
		assert.Equal(t, "us-west1", cfg.DefaultRegion2, "default_region_2 default")
		assert.Equal(t, "US", cfg.DefaultRegionGCS, "default_region_gcs default")
		assert.Equal(t, "us", cfg.DefaultRegionKMS, "default_region_kms default")
		assert.Equal(t, "SOFTWARE", cfg.KMSKeyProtectionLevel, "kms_key_protection_level default")
		assert.Equal(t, "organizations/123456789", cfg.Parent, "parent default")
		assert.Equal(t, "organization", cfg.ParentType, "parent_type default")
		assert.Equal(t, "123456789", cfg.ParentID, "parent_id default")
		assert.True(t, cfg.RandomSuffix, "random_suffix default")
		assert.True(t, cfg.FolderDeletionProtection, "folder_deletion_protection default")
		assert.Equal(t, "WITH_INITIAL_OWNER", cfg.InitialGroupConfig, "initial_group_config default")

		return nil
	}, pulumi.WithMocks("project", "stack", mocks(0)))
	assert.NoError(t, err)
}

func TestConfigParentFolder(t *testing.T) {
	os.Setenv("PULUMI_CONFIG", `{"project:org_id":"123456789", "project:billing_account":"000000-000000-000000", "project:group_org_admins":"org-admins@example.com", "project:group_billing_admins":"billing-admins@example.com", "project:billing_data_users":"billing-users@example.com", "project:audit_data_users":"audit-users@example.com", "project:parent_folder":"987654321"}`)
	defer os.Unsetenv("PULUMI_CONFIG")

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cfg := loadConfig(ctx)

		assert.Equal(t, "folders/987654321", cfg.Parent)
		assert.Equal(t, "folder", cfg.ParentType)
		assert.Equal(t, "987654321", cfg.ParentID)

		return nil
	}, pulumi.WithMocks("project", "stack", mocks(0)))
	assert.NoError(t, err)
}

func TestConfigExplicitFalseDefaults(t *testing.T) {
	os.Setenv("PULUMI_CONFIG", `{"project:org_id":"123456789", "project:billing_account":"000000-000000-000000", "project:group_org_admins":"org-admins@example.com", "project:group_billing_admins":"billing-admins@example.com", "project:billing_data_users":"billing-users@example.com", "project:audit_data_users":"audit-users@example.com", "project:random_suffix":"false", "project:folder_deletion_protection":"false"}`)
	defer os.Unsetenv("PULUMI_CONFIG")

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cfg := loadConfig(ctx)

		assert.False(t, cfg.RandomSuffix, "random_suffix when false")
		assert.False(t, cfg.FolderDeletionProtection, "folder_deletion_protection when false")

		return nil
	}, pulumi.WithMocks("project", "stack", mocks(0)))
	assert.NoError(t, err)
}

// TestSeedProjectStruct verifies the SeedProject output struct.
func TestSeedProjectStruct(t *testing.T) {
	sp := &SeedProject{}
	assert.NotNil(t, sp)
}

// TestCICDProjectStruct verifies the CICDProject output struct.
func TestCICDProjectStruct(t *testing.T) {
	cp := &CICDProject{}
	assert.NotNil(t, cp)
}
