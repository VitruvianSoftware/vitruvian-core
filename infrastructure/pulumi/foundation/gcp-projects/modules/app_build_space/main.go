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

// Package app_build_space declares an application's Artifact Registry
// repository and the identity permitted to push to it.
//
// It is the counterpart to app_deploy_identity: that module mints WHO may
// deploy an app, this one mints WHERE the app's images live and WHO may write
// them. Both are foundation-authored for the same reason — they concern
// resources in projects the foundation owns, and grants that reach outside the
// application.
//
// READERS ARE NOT GRANTED HERE. Pulling an image needs reader on this
// repository for both the Cloud Run service agent and the DEPLOYING identity,
// and those identities are per-environment — they live in the env leaves, which
// apply AFTER this shared leaf. Granting them here would need this leaf to
// reference stacks that do not exist yet. The env leaves grant their own.
package app_build_space

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/artifactregistry"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Deploy creates the repository, the build identity, its WIF binding and the
// writer grant that lets it push.
func Deploy(ctx *pulumi.Context, args *Args) (*Result, error) {
	if args == nil || args.App == "" {
		return nil, fmt.Errorf("app_build_space: App is required")
	}
	if args.Region == "" {
		return nil, fmt.Errorf("app_build_space: Region is required")
	}

	repoID := args.RepositoryID
	if repoID == "" {
		repoID = args.App
	}
	accountID := args.BuildAccountID
	if accountID == "" {
		accountID = args.App + "-build"
	}

	repoArgs := &artifactregistry.RepositoryArgs{
		Project:      args.BuildProjectID,
		Location:     pulumi.String(args.Region),
		RepositoryId: pulumi.String(repoID),
		Format:       pulumi.String("DOCKER"),
		Description: pulumi.String(fmt.Sprintf(
			"%s container images (build-once, promoted by digest). Platform-issued; grants authored in foundation/gcp-projects.",
			args.App,
		)),
	}
	// Retention is a platform policy, not an app preference — which is part of
	// why this repository belongs to the foundation.
	if args.KeepCount > 0 {
		repoArgs.CleanupPolicies = artifactregistry.RepositoryCleanupPolicyArray{
			&artifactregistry.RepositoryCleanupPolicyArgs{
				Id:     pulumi.String("keep-recent"),
				Action: pulumi.String("KEEP"),
				MostRecentVersions: &artifactregistry.RepositoryCleanupPolicyMostRecentVersionsArgs{
					KeepCount: pulumi.Int(args.KeepCount),
				},
			},
		}
	}

	// createIgnoreAlreadyExists so ADOPTING the live repository is not a
	// destructive replace — same pattern app_deploy_identity uses for the
	// deploy SA it took over from the app stack.
	repo, err := artifactregistry.NewRepository(ctx, args.App+"-images", repoArgs,
		pulumi.RetainOnDelete(true))
	if err != nil {
		return nil, fmt.Errorf("app_build_space: repository: %w", err)
	}

	sa, err := serviceaccount.NewAccount(ctx, args.App+"-build-sa", &serviceaccount.AccountArgs{
		Project:                   args.BuildProjectID,
		AccountId:                 pulumi.String(accountID),
		DisplayName:               pulumi.String(fmt.Sprintf("%s image build/push", args.App)),
		Description:               pulumi.String("Platform-issued. Impersonated by GitHub Actions via WIF; pushes images to the app's Artifact Registry repository."),
		CreateIgnoreAlreadyExists: pulumi.Bool(true),
	})
	if err != nil {
		return nil, fmt.Errorf("app_build_space: build sa: %w", err)
	}

	if args.GitHubEnvironment != "" {
		if _, err := serviceaccount.NewIAMMember(ctx, args.App+"-build-wif", &serviceaccount.IAMMemberArgs{
			ServiceAccountId: sa.Name,
			Role:             pulumi.String("roles/iam.workloadIdentityUser"),
			Member: pulumi.Sprintf("principalSet://iam.googleapis.com/%s/attribute.environment/%s",
				args.WorkloadIdentityPool, args.GitHubEnvironment),
		}); err != nil {
			return nil, fmt.Errorf("app_build_space: wif binding: %w", err)
		}
	}

	// WRITER, not admin: the build identity may push images and nothing else.
	// It cannot change who reads the repository — that is the foundation's call.
	if _, err := artifactregistry.NewRepositoryIamMember(ctx, args.App+"-build-writer",
		&artifactregistry.RepositoryIamMemberArgs{
			Project:    args.BuildProjectID,
			Location:   pulumi.String(args.Region),
			Repository: repo.RepositoryId,
			Role:       pulumi.String("roles/artifactregistry.writer"),
			Member:     pulumi.Sprintf("serviceAccount:%s", sa.Email),
		}); err != nil {
		return nil, fmt.Errorf("app_build_space: writer grant: %w", err)
	}

	return &Result{
		RepositoryID:             repo.RepositoryId,
		RepositoryName:           repo.Name,
		BuildServiceAccountEmail: sa.Email,
	}, nil
}
