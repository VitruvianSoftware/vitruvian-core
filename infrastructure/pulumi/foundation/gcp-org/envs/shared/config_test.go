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
		// network_billing_account unset -> falls back to BillingAccount, i.e.
		// every project (including the 4 network ones) funds from the same
		// account, matching pre-carve-out behavior.
		assert.Equal(t, "AAAAAA-BBBBBB-CCCCCC", cfg.NetworkBillingAccount)
		assert.Equal(t, true, cfg.EnableBillingAccountSink)
		assert.Equal(t, "prj", cfg.ProjectPrefix)
		assert.Equal(t, "fldr", cfg.FolderPrefix)
		assert.Equal(t, "us-central1", cfg.DefaultRegion)
		assert.Equal(t, "organizations/123456789", cfg.Parent)
		assert.Equal(t, "organization", cfg.ParentType)
		assert.Equal(t, "123456789", cfg.ParentID)
		assert.Equal(t, false, cfg.EnableHubAndSpoke)
		assert.Empty(t, cfg.DomainsToAllow)
		assert.Empty(t, cfg.EssentialContactsDomains)
		assert.Empty(t, cfg.OSSPublicInvokerProjects)
		assert.Equal(t, "en", cfg.EssentialContactsLanguage)
		assert.Equal(t, "scc-notify", cfg.SCCNotificationName)
		assert.Equal(t, "state = \"ACTIVE\"", cfg.SCCNotificationFilter)
		assert.Equal(t, false, cfg.CreateUniqueTagKey)
		assert.Equal(t, false, cfg.EnableSCCResources)
		assert.Equal(t, true, cfg.EnableKMSKeyUsageTracking)
		assert.Equal(t, true, cfg.CreateAccessContextManagerPolicy)
		assert.Equal(t, false, cfg.EnforceAllowedWorkerPools)
		assert.Equal(t, "PREVENT", cfg.ProjectDeletionPolicy)
		assert.Equal(t, true, cfg.FolderDeletionProtection)
		assert.Equal(t, false, cfg.LogExportStorageForceDestroy)
		assert.Equal(t, false, cfg.LogExportStorageVersioning)

		return nil
	}, pulumi.WithMocks("project", "stack", &mockResourceProvider{}))

	assert.NoError(t, err)
}

// TestOrgConfigNetworkBillingAccountOverride verifies that an explicit
// network_billing_account carves the 4 network-folder projects (net-hub +
// the 3 per-env svpc host projects) off BillingAccount without touching it.
func TestOrgConfigNetworkBillingAccountOverride(t *testing.T) {
	os.Setenv("PULUMI_CONFIG", `{ "project:org_id": "123456789", "project:billing_account": "AAAAAA-BBBBBB-CCCCCC", "project:network_billing_account": "XXXXXX-YYYYYY-ZZZZZZ", "project:bootstrap_stack_name": "bootstrap" }`)
	defer os.Unsetenv("PULUMI_CONFIG")

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cfg := loadOrgConfig(ctx)

		assert.Equal(t, "AAAAAA-BBBBBB-CCCCCC", cfg.BillingAccount)
		assert.Equal(t, "XXXXXX-YYYYYY-ZZZZZZ", cfg.NetworkBillingAccount)

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
