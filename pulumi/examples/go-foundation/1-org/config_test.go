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

// TestOrgConfigDefaults verifies that the OrgConfig struct applies the correct
// defaults matching the Terraform foundation's variables.tf defaults.
func TestOrgConfigDefaults(t *testing.T) {
	os.Setenv("PULUMI_CONFIG", `{ "project:org_id": "123456789", "project:billing_account": "AAAAAA-BBBBBB-CCCCCC", "project:bootstrap_stack_name": "bootstrap" }`)
	defer os.Unsetenv("PULUMI_CONFIG")

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cfg := loadOrgConfig(ctx)

		// Assert that defaults applied inside loadOrgConfig match Terraform upstream.
		assert.Equal(t, "123456789", cfg.OrgID)
		assert.Equal(t, "AAAAAA-BBBBBB-CCCCCC", cfg.BillingAccount)
		assert.Equal(t, false, cfg.EnableBillingAccountSink)
		assert.Equal(t, "prj", cfg.ProjectPrefix)
		assert.Equal(t, "fldr", cfg.FolderPrefix)
		assert.Equal(t, "us-central1", cfg.DefaultRegion)
		assert.Equal(t, "organizations/123456789", cfg.Parent)
		assert.Equal(t, "organization", cfg.ParentType)
		assert.Equal(t, "123456789", cfg.ParentID)
		assert.Equal(t, false, cfg.EnableHubAndSpoke)
		assert.Empty(t, cfg.DomainsToAllow)
		assert.Empty(t, cfg.EssentialContactsDomains)
		assert.Equal(t, "en", cfg.EssentialContactsLanguage)
		assert.Equal(t, "scc-notify", cfg.SCCNotificationName)
		assert.Equal(t, "state = \"ACTIVE\"", cfg.SCCNotificationFilter)
		assert.Equal(t, false, cfg.CreateUniqueTagKey)
		assert.Equal(t, true, cfg.EnableSCCResources) 
		assert.Equal(t, true, cfg.EnableKMSKeyUsageTracking)
		assert.Equal(t, true, cfg.CreateAccessContextManagerPolicy)
		assert.Equal(t, true, cfg.EnforceAllowedWorkerPools)
		assert.Equal(t, "PREVENT", cfg.ProjectDeletionPolicy)
		assert.Equal(t, true, cfg.FolderDeletionProtection)
		assert.Equal(t, false, cfg.LogExportStorageForceDestroy)
		assert.Equal(t, false, cfg.LogExportStorageVersioning) 

		return nil
	}, pulumi.WithMocks("project", "stack", &mockResourceProvider{}))

	assert.NoError(t, err)
}

type mockResourceProvider struct{}

func (m *mockResourceProvider) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return resource.PropertyMap{}, nil
}

func (m *mockResourceProvider) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	return args.Name + "_id", args.Inputs, nil
}
