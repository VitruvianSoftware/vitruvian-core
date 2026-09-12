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
	gcpCSR       = "gcp:sourcerepo/repository:Repository"
	gcpAR        = "gcp:artifactregistry/repository:Repository"
	gcpARIAM     = "gcp:artifactregistry/repositoryIamMember:RepositoryIamMember"
	gcpCBTrigger = "gcp:cloudbuild/trigger:Trigger"
)

// basicCloudBuildArgs returns default args using GitHub source (the default).
func basicCloudBuildArgs() *CloudBuildArgs {
	return &CloudBuildArgs{
		ProjectID:  pulumi.String("prj-cicd-789"),
		Region:     pulumi.String("us-central1"),
		SourceType: CloudBuildSourceGitHub,
		Triggers: map[string]CloudBuildTriggerConfig{
			"bootstrap": {
				RepoName:       "gcp-bootstrap",
				RepoOwner:      "my-org",
				ServiceAccount: pulumi.String("projects/prj-cicd-789/serviceAccounts/sa-bootstrap@prj-cicd-789.iam.gserviceaccount.com"),
			},
		},
		ArtifactRegistryReaders: []pulumi.StringInput{
			pulumi.String("serviceAccount:sa-bootstrap@prj-cicd-789.iam.gserviceaccount.com"),
		},
	}
}

// ========================================================================
// Nil Guard
// ========================================================================

func TestNewCloudBuild_NilArgs(t *testing.T) {
	_, err := NewCloudBuild(nil, "test", nil)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "args cannot be nil")
}

// ========================================================================
// Basic Creation
// ========================================================================

func TestNewCloudBuild_CreatesAllResources(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cb, err := NewCloudBuild(ctx, "test-cb", basicCloudBuildArgs())
		require.NoError(t, err)
		assert.NotNil(t, cb.ArtifactRegistry)
		assert.Len(t, cb.PlanTriggers, 1)
		assert.Len(t, cb.ApplyTriggers, 1)
		// No CSR repos for GitHub source type
		assert.Len(t, cb.SourceRepos, 0)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	assert.Equal(t, 0, tracker.TypeCount(gcpCSR)) // No CSR repos
	tracker.RequireType(t, gcpAR, 1)
	tracker.RequireType(t, gcpCBTrigger, 2) // 1 plan + 1 apply
	tracker.RequireType(t, gcpARIAM, 1)
}

// ========================================================================
// Source Type: GitHub (Default)
// ========================================================================

func TestNewCloudBuild_DefaultsToGitHub(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicCloudBuildArgs()
		args.SourceType = "" // Should default to GitHub
		_, err := NewCloudBuild(ctx, "test-default-gh", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	// Should use GitHub triggers, not CSR
	assert.Equal(t, 0, tracker.TypeCount(gcpCSR))
	triggers := tracker.RequireType(t, gcpCBTrigger, 2)
	// Verify at least one trigger has a github block
	hasGithub := false
	for _, tr := range triggers {
		if gh := tr.Inputs["github"]; gh.IsObject() {
			hasGithub = true
			assert.Equal(t, "my-org", gh.ObjectValue()["owner"].StringValue())
			assert.Equal(t, "gcp-bootstrap", gh.ObjectValue()["name"].StringValue())
		}
	}
	assert.True(t, hasGithub, "at least one trigger should have a github block")
}

func TestNewCloudBuild_GitHubTriggersHaveOwner(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCloudBuild(ctx, "test-gh-owner", basicCloudBuildArgs())
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	triggers := tracker.RequireType(t, gcpCBTrigger, 2)
	for _, tr := range triggers {
		gh := tr.Inputs["github"]
		if gh.IsObject() {
			assert.Equal(t, "my-org", gh.ObjectValue()["owner"].StringValue())
		}
	}
}

// ========================================================================
// Source Type: CSR (Legacy)
// ========================================================================

func TestNewCloudBuild_CSR_CreatesSourceRepos(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicCloudBuildArgs()
		args.SourceType = CloudBuildSourceCSR
		args.SourceRepos = []string{"gcp-bootstrap", "gcp-org", "gcp-policies"}
		args.Triggers["bootstrap"] = CloudBuildTriggerConfig{
			RepoName:       "gcp-bootstrap",
			ServiceAccount: pulumi.String("projects/prj/serviceAccounts/sa@prj.iam.gserviceaccount.com"),
		}
		cb, err := NewCloudBuild(ctx, "test-csr", args)
		require.NoError(t, err)
		assert.Len(t, cb.SourceRepos, 3)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, gcpCSR, 3)
}

func TestNewCloudBuild_CSR_UsesTriggerTemplate(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicCloudBuildArgs()
		args.SourceType = CloudBuildSourceCSR
		args.Triggers["bootstrap"] = CloudBuildTriggerConfig{
			RepoName:       "gcp-bootstrap",
			ServiceAccount: pulumi.String("projects/prj/serviceAccounts/sa@prj.iam.gserviceaccount.com"),
		}
		_, err := NewCloudBuild(ctx, "test-csr-template", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	triggers := tracker.RequireType(t, gcpCBTrigger, 2)
	hasTemplate := false
	for _, tr := range triggers {
		if tmpl := tr.Inputs["triggerTemplate"]; tmpl.IsObject() {
			hasTemplate = true
		}
	}
	assert.True(t, hasTemplate, "CSR triggers should use triggerTemplate")
}

func TestNewCloudBuild_GitHub_NoSourceRepos(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicCloudBuildArgs()
		// Even if SourceRepos is set, GitHub mode ignores them
		args.SourceRepos = []string{"gcp-bootstrap", "gcp-org"}
		_, err := NewCloudBuild(ctx, "test-gh-no-csr", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	assert.Equal(t, 0, tracker.TypeCount(gcpCSR), "GitHub mode should not create CSR repos")
}

// ========================================================================
// Source Type: GitLab
// ========================================================================

func TestNewCloudBuild_GitLab_UsesSourceToBuild(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicCloudBuildArgs()
		args.SourceType = CloudBuildSourceGitLab
		args.Triggers["bootstrap"] = CloudBuildTriggerConfig{
			RepoName:       "gcp-bootstrap",
			RepoOwner:      "my-group",
			ServiceAccount: pulumi.String("projects/prj/serviceAccounts/sa@prj.iam.gserviceaccount.com"),
		}
		_, err := NewCloudBuild(ctx, "test-gl-stb", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	triggers := tracker.RequireType(t, gcpCBTrigger, 2)
	hasSourceToBuild := false
	for _, tr := range triggers {
		if stb := tr.Inputs["sourceToBuild"]; stb.IsObject() {
			hasSourceToBuild = true
			assert.Equal(t, "GITLAB", stb.ObjectValue()["repoType"].StringValue())
			assert.Contains(t, stb.ObjectValue()["uri"].StringValue(), "gitlab.com/my-group/gcp-bootstrap")
		}
	}
	assert.True(t, hasSourceToBuild, "GitLab triggers should use sourceToBuild")
}

// ========================================================================
// Artifact Registry
// ========================================================================

func TestNewCloudBuild_ArtifactRegistryDefault(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCloudBuild(ctx, "test-ar-default", basicCloudBuildArgs())
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	repos := tracker.RequireType(t, gcpAR, 1)
	assert.Equal(t, "pulumi-builders", repos[0].Inputs["repositoryId"].StringValue())
	assert.Equal(t, "DOCKER", repos[0].Inputs["format"].StringValue())
}

func TestNewCloudBuild_ArtifactRegistryCustomID(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicCloudBuildArgs()
		args.ArtifactRegistryID = "custom-builders"
		_, err := NewCloudBuild(ctx, "test-ar-custom", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	repos := tracker.RequireType(t, gcpAR, 1)
	assert.Equal(t, "custom-builders", repos[0].Inputs["repositoryId"].StringValue())
}

// ========================================================================
// AR IAM Readers
// ========================================================================

func TestNewCloudBuild_ARReadersCount(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicCloudBuildArgs()
		args.ArtifactRegistryReaders = []pulumi.StringInput{
			pulumi.String("serviceAccount:sa1@prj.iam.gserviceaccount.com"),
			pulumi.String("serviceAccount:sa2@prj.iam.gserviceaccount.com"),
			pulumi.String("serviceAccount:sa3@prj.iam.gserviceaccount.com"),
		}
		_, err := NewCloudBuild(ctx, "test-ar-readers", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	bindings := tracker.RequireType(t, gcpARIAM, 3)
	for _, b := range bindings {
		assert.Equal(t, "roles/artifactregistry.reader", b.Inputs["role"].StringValue())
	}
}

func TestNewCloudBuild_NoARReaders(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicCloudBuildArgs()
		args.ArtifactRegistryReaders = nil
		_, err := NewCloudBuild(ctx, "test-no-readers", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	assert.Equal(t, 0, tracker.TypeCount(gcpARIAM))
}

// ========================================================================
// Cloud Build Triggers — General
// ========================================================================

func TestNewCloudBuild_TriggerPairPerStage(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicCloudBuildArgs()
		args.Triggers["org"] = CloudBuildTriggerConfig{
			RepoName:       "gcp-org",
			RepoOwner:      "my-org",
			ServiceAccount: pulumi.String("projects/prj-cicd-789/serviceAccounts/sa-org@prj-cicd-789.iam.gserviceaccount.com"),
		}
		args.Triggers["env"] = CloudBuildTriggerConfig{
			RepoName:       "gcp-environments",
			RepoOwner:      "my-org",
			ServiceAccount: pulumi.String("projects/prj-cicd-789/serviceAccounts/sa-env@prj-cicd-789.iam.gserviceaccount.com"),
		}
		cb, err := NewCloudBuild(ctx, "test-triggers", args)
		require.NoError(t, err)
		assert.Len(t, cb.PlanTriggers, 3)
		assert.Len(t, cb.ApplyTriggers, 3)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	// 3 stages × 2 (plan + apply) = 6 triggers
	tracker.RequireType(t, gcpCBTrigger, 6)
}

func TestNewCloudBuild_EmptyTriggers(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicCloudBuildArgs()
		args.Triggers = map[string]CloudBuildTriggerConfig{}
		_, err := NewCloudBuild(ctx, "test-no-triggers", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	assert.Equal(t, 0, tracker.TypeCount(gcpCBTrigger))
}

func TestNewCloudBuild_DefaultFilenames(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCloudBuild(ctx, "test-defaults", basicCloudBuildArgs())
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	triggers := tracker.RequireType(t, gcpCBTrigger, 2)
	filenames := make(map[string]bool)
	for _, tr := range triggers {
		filenames[tr.Inputs["filename"].StringValue()] = true
	}
	assert.True(t, filenames["cloudbuild-pulumi-plan.yaml"], "plan trigger should use default filename")
	assert.True(t, filenames["cloudbuild-pulumi-apply.yaml"], "apply trigger should use default filename")
}

func TestNewCloudBuild_CustomFilenames(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicCloudBuildArgs()
		args.Triggers["bootstrap"] = CloudBuildTriggerConfig{
			RepoName:       "gcp-bootstrap",
			RepoOwner:      "my-org",
			ServiceAccount: pulumi.String("projects/prj/serviceAccounts/sa@prj.iam.gserviceaccount.com"),
			PlanFilename:   "custom-plan.yaml",
			ApplyFilename:  "custom-apply.yaml",
		}
		_, err := NewCloudBuild(ctx, "test-custom-files", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	triggers := tracker.RequireType(t, gcpCBTrigger, 2)
	filenames := make(map[string]bool)
	for _, tr := range triggers {
		filenames[tr.Inputs["filename"].StringValue()] = true
	}
	assert.True(t, filenames["custom-plan.yaml"])
	assert.True(t, filenames["custom-apply.yaml"])
}

func TestNewCloudBuild_CustomApplyBranch(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicCloudBuildArgs()
		args.Triggers["bootstrap"] = CloudBuildTriggerConfig{
			RepoName:           "gcp-bootstrap",
			RepoOwner:          "my-org",
			ServiceAccount:     pulumi.String("projects/prj/serviceAccounts/sa@prj.iam.gserviceaccount.com"),
			ApplyBranchPattern: "^production$",
		}
		_, err := NewCloudBuild(ctx, "test-custom-branch", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	triggers := tracker.RequireType(t, gcpCBTrigger, 2)
	// Verify the apply trigger uses the custom branch pattern
	for _, tr := range triggers {
		gh := tr.Inputs["github"]
		if gh.IsObject() {
			push := gh.ObjectValue()["push"]
			if push.IsObject() {
				branch := push.ObjectValue()["branch"].StringValue()
				if branch != ".*" { // Skip plan trigger
					assert.Equal(t, "^production$", branch)
				}
			}
		}
	}
}
