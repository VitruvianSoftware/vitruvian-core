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
		// Co-tenancy: the authoritative org-level billing.creator binding must be
		// OFF by default so a second foundation does not clobber foundation-0.
		assert.False(t, cfg.EnforceOrgBillingCreator, "enforce_org_billing_creator default false")

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

// TestConfigBootstrapSAEmail guards the key that selects the deterministic
// projects.update ordering: unset => empty => legacy in-deployIAM grant path
// (metadataGrant.Active=false); set => loaded verbatim as the string member that
// binds the grant and gates the seed/cicd label updates. A wrong value here would
// bind the wrong principal / replace the org-role binding the SA uses, so the exact
// round-trip matters.
func TestConfigBootstrapSAEmail(t *testing.T) {
	base := `"project:org_id":"123456789", "project:billing_account":"000000-000000-000000", "project:group_org_admins":"org-admins@example.com", "project:group_billing_admins":"billing-admins@example.com", "project:billing_data_users":"billing-users@example.com", "project:audit_data_users":"audit-users@example.com"`

	// Unset => empty => legacy path.
	os.Setenv("PULUMI_CONFIG", "{"+base+"}")
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		assert.Empty(t, loadConfig(ctx).BootstrapSAEmail, "unset => empty => legacy grant path")
		return nil
	}, pulumi.WithMocks("project", "stack", mocks(0)))
	assert.NoError(t, err)
	os.Unsetenv("PULUMI_CONFIG")

	// Set => loaded verbatim (deterministic path member).
	os.Setenv("PULUMI_CONFIG", "{"+base+`, "project:bootstrap_sa_email":"sa-terraform-bootstrap@prj-b-seed-8ebb.iam.gserviceaccount.com"}`)
	defer os.Unsetenv("PULUMI_CONFIG")
	err = pulumi.RunErr(func(ctx *pulumi.Context) error {
		assert.Equal(t, "sa-terraform-bootstrap@prj-b-seed-8ebb.iam.gserviceaccount.com", loadConfig(ctx).BootstrapSAEmail)
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
