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
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/artifactregistry"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/cloudbuild"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/sourcerepo"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// CloudBuildSourceType specifies how Cloud Build triggers connect to source
// repositories. Google deprecated Cloud Source Repositories (CSR) for new
// customers in June 2024, so GitHub and GitLab are the recommended backends.
type CloudBuildSourceType string

const (
	// CloudBuildSourceCSR uses Cloud Source Repositories (legacy).
	// Only available for GCP organizations that had CSR enabled before
	// the June 2024 deprecation. New customers cannot use this option.
	CloudBuildSourceCSR CloudBuildSourceType = "CSR"
	// CloudBuildSourceGitHub uses the Cloud Build GitHub App connection.
	// Requires prior installation of the Cloud Build GitHub App via the
	// GCP Console: Cloud Build → Triggers → Connect Repository.
	CloudBuildSourceGitHub CloudBuildSourceType = "GITHUB"
	// CloudBuildSourceGitLab uses a Cloud Build GitLab host connection.
	// Requires a Cloud Build repository connection configured via
	// GCP Console or the cloudbuildv2 API.
	CloudBuildSourceGitLab CloudBuildSourceType = "GITLAB"
)

// CloudBuildTriggerConfig describes a per-stage Cloud Build trigger pair
// (plan + apply). Each stage maps to a source repository and a service
// account that the trigger runs as.
type CloudBuildTriggerConfig struct {
	// RepoName is the source repository name. For CSR, this is the CSR repo
	// name. For GitHub, this is the GitHub repo name. For GitLab, this is
	// the GitLab project name.
	RepoName string
	// RepoOwner is the GitHub user/org or GitLab namespace that owns the
	// repo. Ignored for CSR (CSR repos are project-scoped). Required for
	// GitHub and GitLab source types.
	RepoOwner string
	// ServiceAccount is the full SA resource name for the trigger
	// (e.g., "projects/prj/serviceAccounts/sa@prj.iam.gserviceaccount.com").
	ServiceAccount pulumi.StringInput
	// PlanFilename is the Cloud Build config file for plan/preview triggers.
	// Defaults to "cloudbuild-pulumi-plan.yaml" if empty.
	PlanFilename string
	// ApplyFilename is the Cloud Build config file for apply triggers.
	// Defaults to "cloudbuild-pulumi-apply.yaml" if empty.
	ApplyFilename string
	// ApplyBranchPattern is the regex for branches that trigger apply.
	// Defaults to "^main$" if empty.
	ApplyBranchPattern string
}

// CloudBuildArgs configures a Cloud Build CI/CD pipeline, mirroring the
// Terraform foundation's build_cb.tf which consumes tf_cloudbuild_source,
// tf_cloudbuild_builder, and tf_cloudbuild_workspace modules.
//
// NOTE: Google deprecated Cloud Source Repositories for new customers in
// June 2024. Set SourceType to CloudBuildSourceGitHub or
// CloudBuildSourceGitLab for new deployments.
type CloudBuildArgs struct {
	// ProjectID is the GCP project hosting the Cloud Build infrastructure.
	ProjectID pulumi.StringInput
	// Region is the GCP region for Artifact Registry and triggers.
	Region pulumi.StringInput
	// SourceType specifies how triggers connect to source repos.
	// Defaults to CloudBuildSourceGitHub if empty.
	SourceType CloudBuildSourceType
	// SourceRepos is the list of Cloud Source Repository names to create.
	// Only used when SourceType is CloudBuildSourceCSR. Ignored for GitHub
	// and GitLab source types (those repos are managed externally).
	SourceRepos []string
	// ArtifactRegistryID is the Artifact Registry repository ID
	// (e.g., "pulumi-builders"). Defaults to "pulumi-builders" if empty.
	ArtifactRegistryID string
	// Triggers maps logical stage keys to their trigger configurations.
	// Each entry creates a plan + apply Cloud Build trigger pair.
	Triggers map[string]CloudBuildTriggerConfig
	// ArtifactRegistryReaders are IAM members granted reader access
	// to the Artifact Registry (e.g., service account emails as
	// "serviceAccount:sa@project.iam.gserviceaccount.com").
	ArtifactRegistryReaders []pulumi.StringInput
}

// CloudBuild represents a Cloud Build CI/CD infrastructure configuration.
type CloudBuild struct {
	pulumi.ResourceState
	// SourceRepos maps repo names to their Cloud Source Repository resources.
	// Only populated when SourceType is CloudBuildSourceCSR.
	SourceRepos map[string]*sourcerepo.Repository
	// ArtifactRegistry is the Artifact Registry repository for builder images.
	ArtifactRegistry *artifactregistry.Repository
	// PlanTriggers maps stage keys to their plan/preview triggers.
	PlanTriggers map[string]*cloudbuild.Trigger
	// ApplyTriggers maps stage keys to their apply triggers.
	ApplyTriggers map[string]*cloudbuild.Trigger
}

// NewCloudBuild creates a new CloudBuild component resource.
func NewCloudBuild(ctx *pulumi.Context, name string, args *CloudBuildArgs, opts ...pulumi.ResourceOption) (*CloudBuild, error) {
	if args == nil {
		return nil, fmt.Errorf("args cannot be nil")
	}
	component := &CloudBuild{
		SourceRepos:   make(map[string]*sourcerepo.Repository),
		PlanTriggers:  make(map[string]*cloudbuild.Trigger),
		ApplyTriggers: make(map[string]*cloudbuild.Trigger),
	}
	err := ctx.RegisterComponentResource("pkg:cicd:CloudBuild", name, component, opts...)
	if err != nil {
		return nil, err
	}

	// Default source type to GitHub (CSR is deprecated for new customers)
	sourceType := args.SourceType
	if sourceType == "" {
		sourceType = CloudBuildSourceGitHub
	}

	// ========================================================================
	// 1. Cloud Source Repositories (CSR only — legacy)
	// ========================================================================
	if sourceType == CloudBuildSourceCSR {
		for _, repoName := range args.SourceRepos {
			repo, err := sourcerepo.NewRepository(ctx, fmt.Sprintf("%s-csr-%s", name, repoName), &sourcerepo.RepositoryArgs{
				Project: args.ProjectID,
				Name:    pulumi.String(repoName),
			}, pulumi.Parent(component))
			if err != nil {
				return nil, err
			}
			component.SourceRepos[repoName] = repo
		}
	}

	// ========================================================================
	// 2. Artifact Registry
	// ========================================================================
	arID := args.ArtifactRegistryID
	if arID == "" {
		arID = "pulumi-builders"
	}

	arRepo, err := artifactregistry.NewRepository(ctx, name+"-ar", &artifactregistry.RepositoryArgs{
		Project:      args.ProjectID,
		RepositoryId: pulumi.String(arID),
		Location:     args.Region,
		Format:       pulumi.String("DOCKER"),
		Description:  pulumi.String("Builder images for Cloud Build pipelines. Managed by Pulumi."),
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.ArtifactRegistry = arRepo

	// Grant reader access to specified members
	for i, member := range args.ArtifactRegistryReaders {
		_, err := artifactregistry.NewRepositoryIamMember(ctx, fmt.Sprintf("%s-ar-reader-%d", name, i), &artifactregistry.RepositoryIamMemberArgs{
			Project:    args.ProjectID,
			Location:   args.Region,
			Repository: arRepo.RepositoryId,
			Role:       pulumi.String("roles/artifactregistry.reader"),
			Member:     member,
		}, pulumi.Parent(arRepo))
		if err != nil {
			return nil, err
		}
	}

	// ========================================================================
	// 3. Cloud Build Triggers (plan + apply per stage)
	// ========================================================================
	for key, cfg := range args.Triggers {
		planFilename := cfg.PlanFilename
		if planFilename == "" {
			planFilename = "cloudbuild-pulumi-plan.yaml"
		}
		applyFilename := cfg.ApplyFilename
		if applyFilename == "" {
			applyFilename = "cloudbuild-pulumi-apply.yaml"
		}
		applyBranch := cfg.ApplyBranchPattern
		if applyBranch == "" {
			applyBranch = "^main$"
		}

		// Build source-specific trigger args
		planArgs, applyArgs := buildTriggerArgs(args, cfg, key, planFilename, applyFilename, applyBranch, sourceType)

		planTrigger, err := cloudbuild.NewTrigger(ctx, fmt.Sprintf("%s-plan-%s", name, key), planArgs, pulumi.Parent(component))
		if err != nil {
			return nil, err
		}
		component.PlanTriggers[key] = planTrigger

		applyTrigger, err := cloudbuild.NewTrigger(ctx, fmt.Sprintf("%s-apply-%s", name, key), applyArgs, pulumi.Parent(component))
		if err != nil {
			return nil, err
		}
		component.ApplyTriggers[key] = applyTrigger
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{
		"artifactRegistryName": arRepo.Name,
	})

	return component, nil
}

// buildTriggerArgs constructs the plan and apply trigger args based on the
// source type. This factory handles the divergent trigger configuration
// between CSR, GitHub, and GitLab backends.
func buildTriggerArgs(
	args *CloudBuildArgs,
	cfg CloudBuildTriggerConfig,
	key, planFilename, applyFilename, applyBranch string,
	sourceType CloudBuildSourceType,
) (*cloudbuild.TriggerArgs, *cloudbuild.TriggerArgs) {
	basePlan := &cloudbuild.TriggerArgs{
		Project:        args.ProjectID,
		Name:           pulumi.String(fmt.Sprintf("plan-%s", key)),
		Description:    pulumi.String(fmt.Sprintf("Pulumi preview for %s stage. Managed by Pulumi.", key)),
		Filename:       pulumi.String(planFilename),
		Location:       args.Region,
		ServiceAccount: cfg.ServiceAccount,
	}
	baseApply := &cloudbuild.TriggerArgs{
		Project:        args.ProjectID,
		Name:           pulumi.String(fmt.Sprintf("apply-%s", key)),
		Description:    pulumi.String(fmt.Sprintf("Pulumi up for %s stage. Managed by Pulumi.", key)),
		Filename:       pulumi.String(applyFilename),
		Location:       args.Region,
		ServiceAccount: cfg.ServiceAccount,
	}

	switch sourceType {
	case CloudBuildSourceGitHub:
		basePlan.Github = &cloudbuild.TriggerGithubArgs{
			Owner: pulumi.String(cfg.RepoOwner),
			Name:  pulumi.String(cfg.RepoName),
			Push: &cloudbuild.TriggerGithubPushArgs{
				Branch: pulumi.String(".*"),
			},
		}
		baseApply.Github = &cloudbuild.TriggerGithubArgs{
			Owner: pulumi.String(cfg.RepoOwner),
			Name:  pulumi.String(cfg.RepoName),
			Push: &cloudbuild.TriggerGithubPushArgs{
				Branch: pulumi.String(applyBranch),
			},
		}
	case CloudBuildSourceGitLab:
		// GitLab uses SourceToBuild + GitFileSource for connected repos.
		// The URI format is the HTTPS clone URL of the GitLab project.
		gitlabURI := pulumi.String(fmt.Sprintf("https://gitlab.com/%s/%s", cfg.RepoOwner, cfg.RepoName))
		basePlan.SourceToBuild = &cloudbuild.TriggerSourceToBuildArgs{
			Uri:      gitlabURI,
			Ref:      pulumi.String("refs/heads/main"),
			RepoType: pulumi.String("GITLAB"),
		}
		basePlan.GitFileSource = &cloudbuild.TriggerGitFileSourceArgs{
			Path:     pulumi.String(planFilename),
			Uri:      gitlabURI,
			Revision: pulumi.String("refs/heads/main"),
			RepoType: pulumi.String("GITLAB"),
		}
		baseApply.SourceToBuild = &cloudbuild.TriggerSourceToBuildArgs{
			Uri:      gitlabURI,
			Ref:      pulumi.String("refs/heads/main"),
			RepoType: pulumi.String("GITLAB"),
		}
		baseApply.GitFileSource = &cloudbuild.TriggerGitFileSourceArgs{
			Path:     pulumi.String(applyFilename),
			Uri:      gitlabURI,
			Revision: pulumi.String("refs/heads/main"),
			RepoType: pulumi.String("GITLAB"),
		}
	default: // CSR
		basePlan.TriggerTemplate = &cloudbuild.TriggerTriggerTemplateArgs{
			ProjectId:  args.ProjectID,
			RepoName:   pulumi.String(cfg.RepoName),
			BranchName: pulumi.String(".*"),
		}
		baseApply.TriggerTemplate = &cloudbuild.TriggerTriggerTemplateArgs{
			ProjectId:  args.ProjectID,
			RepoName:   pulumi.String(cfg.RepoName),
			BranchName: pulumi.String(applyBranch),
		}
	}

	return basePlan, baseApply
}
