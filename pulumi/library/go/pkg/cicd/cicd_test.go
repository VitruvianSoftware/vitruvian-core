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

package cicd

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	gcpWIFPool     = "gcp:iam/workloadIdentityPool:WorkloadIdentityPool"
	gcpWIFProvider = "gcp:iam/workloadIdentityPoolProvider:WorkloadIdentityPoolProvider"
	gcpSAIAM       = "gcp:serviceaccount/iAMMember:IAMMember"
)

// ========================================================================
// GitHub OIDC Tests
// ========================================================================

func basicGitHubArgs() *GitHubOIDCArgs {
	return &GitHubOIDCArgs{
		ProjectID:          pulumi.String("prj-cicd-123"),
		PoolID:             pulumi.String("foundation-pool"),
		ProviderID:         pulumi.String("foundation-gh-provider"),
		AttributeCondition: pulumi.String("assertion.repository_owner=='my-org'"),
		SAMapping: map[string]SAMappingEntry{
			"bootstrap": {
				SAName:    pulumi.String("projects/prj-cicd-123/serviceAccounts/bootstrap@prj-cicd-123.iam.gserviceaccount.com"),
				Attribute: pulumi.String("attribute.repository/my-org/gcp-bootstrap"),
			},
		},
	}
}

func TestNewGitHubOIDC_NilArgs(t *testing.T) {
	_, err := NewGitHubOIDC(nil, "test", nil)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "args cannot be nil")
}

func TestNewGitHubOIDC_CreatesPoolAndProvider(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		gh, err := NewGitHubOIDC(ctx, "test-gh", basicGitHubArgs())
		require.NoError(t, err)
		assert.NotNil(t, gh.Pool)
		assert.NotNil(t, gh.Provider)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, gcpWIFPool, 1)
	tracker.RequireType(t, gcpWIFProvider, 1)
}

func TestNewGitHubOIDC_PoolConfig(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewGitHubOIDC(ctx, "test-pool", basicGitHubArgs())
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	pools := tracker.RequireType(t, gcpWIFPool, 1)
	assert.Equal(t, "foundation-pool", pools[0].Inputs["workloadIdentityPoolId"].StringValue())
	assert.Equal(t, false, pools[0].Inputs["disabled"].BoolValue())
}

func TestNewGitHubOIDC_ProviderConfig(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewGitHubOIDC(ctx, "test-provider", basicGitHubArgs())
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	providers := tracker.RequireType(t, gcpWIFProvider, 1)
	assert.Equal(t, "foundation-gh-provider",
		providers[0].Inputs["workloadIdentityPoolProviderId"].StringValue())
	assert.Equal(t, "assertion.repository_owner=='my-org'",
		providers[0].Inputs["attributeCondition"].StringValue())
}

func TestNewGitHubOIDC_SABindings(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicGitHubArgs()
		args.SAMapping["org"] = SAMappingEntry{
			SAName:    pulumi.String("projects/prj-cicd-123/serviceAccounts/org@prj-cicd-123.iam.gserviceaccount.com"),
			Attribute: pulumi.String("attribute.repository/my-org/gcp-org"),
		}
		gh, err := NewGitHubOIDC(ctx, "test-bindings", args)
		require.NoError(t, err)
		assert.Len(t, gh.Bindings, 2)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	bindings := tracker.RequireType(t, gcpSAIAM, 2)
	for _, b := range bindings {
		assert.Equal(t, "roles/iam.workloadIdentityUser", b.Inputs["role"].StringValue())
	}
}

func TestNewGitHubOIDC_EmptyMapping(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicGitHubArgs()
		args.SAMapping = map[string]SAMappingEntry{}
		gh, err := NewGitHubOIDC(ctx, "test-empty", args)
		require.NoError(t, err)
		assert.Len(t, gh.Bindings, 0)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	assert.Equal(t, 0, tracker.TypeCount(gcpSAIAM))
}

// ========================================================================
// GitLab OIDC Tests
// ========================================================================

func basicGitLabArgs() *GitLabOIDCArgs {
	return &GitLabOIDCArgs{
		ProjectID:          pulumi.String("prj-cicd-456"),
		PoolID:             pulumi.String("foundation-pool"),
		ProviderID:         pulumi.String("foundation-gl-provider"),
		AttributeCondition: pulumi.String("assertion.project_path.startsWith('my-group/')"),
		SAMapping: map[string]SAMappingEntry{
			"bootstrap": {
				SAName:    pulumi.String("projects/prj-cicd-456/serviceAccounts/bootstrap@prj-cicd-456.iam.gserviceaccount.com"),
				Attribute: pulumi.String("attribute.project_path/my-group/gcp-bootstrap"),
			},
		},
	}
}

func TestNewGitLabOIDC_NilArgs(t *testing.T) {
	_, err := NewGitLabOIDC(nil, "test", nil)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "args cannot be nil")
}

func TestNewGitLabOIDC_CreatesPoolAndProvider(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		gl, err := NewGitLabOIDC(ctx, "test-gl", basicGitLabArgs())
		require.NoError(t, err)
		assert.NotNil(t, gl.Pool)
		assert.NotNil(t, gl.Provider)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, gcpWIFPool, 1)
	tracker.RequireType(t, gcpWIFProvider, 1)
}

func TestNewGitLabOIDC_ProviderConfig(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewGitLabOIDC(ctx, "test-gl-provider", basicGitLabArgs())
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	providers := tracker.RequireType(t, gcpWIFProvider, 1)
	assert.Equal(t, "foundation-gl-provider",
		providers[0].Inputs["workloadIdentityPoolProviderId"].StringValue())
}

func TestNewGitLabOIDC_DefaultIssuerUri(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicGitLabArgs()
		// IssuerUri is nil → should default to https://gitlab.com
		_, err := NewGitLabOIDC(ctx, "test-gl-issuer", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	providers := tracker.RequireType(t, gcpWIFProvider, 1)
	oidc := providers[0].Inputs["oidc"]
	require.True(t, oidc.IsObject())
	issuer := oidc.ObjectValue()["issuerUri"]
	assert.Equal(t, "https://gitlab.com", issuer.StringValue())
}

func TestNewGitLabOIDC_CustomIssuerUri(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicGitLabArgs()
		args.IssuerUri = pulumi.String("https://gitlab.mycompany.com")
		_, err := NewGitLabOIDC(ctx, "test-gl-custom-issuer", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	providers := tracker.RequireType(t, gcpWIFProvider, 1)
	oidc := providers[0].Inputs["oidc"]
	require.True(t, oidc.IsObject())
	issuer := oidc.ObjectValue()["issuerUri"]
	assert.Equal(t, "https://gitlab.mycompany.com", issuer.StringValue())
}

func TestNewGitLabOIDC_AttributeMappingCount(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewGitLabOIDC(ctx, "test-gl-attrs", basicGitLabArgs())
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	providers := tracker.RequireType(t, gcpWIFProvider, 1)
	mapping := providers[0].Inputs["attributeMapping"]
	require.True(t, mapping.IsObject())
	// The TF gitlab-oidc module maps 14 attributes (google.subject + 13 custom).
	// We map the same set: google.subject, 7 standard claims, 7 GitLab custom claims = 15 total entries.
	// However google.subject + attribute.sub both map from assertion.sub so there are 15 keys.
	assert.Equal(t, 15, len(mapping.ObjectValue()),
		"attribute mapping should contain all 15 entries matching the TF module defaults")
}

func TestNewGitLabOIDC_SABindings(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicGitLabArgs()
		args.SAMapping["org"] = SAMappingEntry{
			SAName:    pulumi.String("projects/prj-cicd-456/serviceAccounts/org@prj-cicd-456.iam.gserviceaccount.com"),
			Attribute: pulumi.String("attribute.project_path/my-group/gcp-org"),
		}
		gl, err := NewGitLabOIDC(ctx, "test-gl-bindings", args)
		require.NoError(t, err)
		assert.Len(t, gl.Bindings, 2)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	bindings := tracker.RequireType(t, gcpSAIAM, 2)
	for _, b := range bindings {
		assert.Equal(t, "roles/iam.workloadIdentityUser", b.Inputs["role"].StringValue())
	}
}

func TestNewGitLabOIDC_EmptyMapping(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicGitLabArgs()
		args.SAMapping = map[string]SAMappingEntry{}
		gl, err := NewGitLabOIDC(ctx, "test-gl-empty", args)
		require.NoError(t, err)
		assert.Len(t, gl.Bindings, 0)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	assert.Equal(t, 0, tracker.TypeCount(gcpSAIAM))
}
