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
	"fmt"

	"github.com/VitruvianSoftware/pulumi-library/go/pkg/bootstrap/v2"
	libstorage "github.com/VitruvianSoftware/pulumi-library/go/pkg/cloud_storage"
	project "github.com/VitruvianSoftware/pulumi-library/go/pkg/project_factory"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/organizations"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/storage"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// deployBootstrapFolder creates the top-level bootstrap folder that parents
// the seed and CI/CD projects.
// Mirrors: google_folder.bootstrap in the TF foundation's 0-bootstrap/main.tf.
func deployBootstrapFolder(ctx *pulumi.Context, cfg *Config) (*organizations.Folder, pulumi.StringOutput, error) {
	bootstrapFolder, err := organizations.NewFolder(ctx, "bootstrap-folder", &organizations.FolderArgs{
		DisplayName:        pulumi.String(cfg.FolderPrefix + "-bootstrap"),
		Parent:             pulumi.String(cfg.Parent),
		DeletionProtection: pulumi.Bool(cfg.FolderDeletionProtection),
	}, pulumi.Protect(true))
	if err != nil {
		return nil, pulumi.StringOutput{}, err
	}

	// Convert IDOutput to StringOutput for folder ID
	folderID := bootstrapFolder.ID().ApplyT(func(id pulumi.ID) string {
		return string(id)
	}).(pulumi.StringOutput)

	return bootstrapFolder, folderID, nil
}

// SeedProject holds outputs from the seed project deployment.
type SeedProject struct {
	ProjectID               pulumi.StringOutput
	StateBucketName         pulumi.StringOutput
	ProjectsStateBucketName pulumi.StringOutput // Separate bucket for 4-projects stage
	KMSKeyID                pulumi.StringOutput
	// APIsReady gates on the seed project's ActivateApis being enabled AND
	// propagated (project_factory's ApisReady). Downstream resources that call a
	// seed-project API on a COLD deploy — the granular SAs (iam API), bucket-IAM,
	// etc. — must DependsOn it so the first apply never races API enablement.
	APIsReady pulumi.Resource
}

// CICDProject holds outputs from the CI/CD project deployment.
type CICDProject struct {
	ProjectID pulumi.StringOutput
}

// deploySeedProject creates the seed project that hosts Terraform/Pulumi state
// and the service accounts used by the foundation pipeline. This uses the
// Bootstrap component from the Vitruvian Pulumi Library, which mirrors the
// upstream terraform-google-modules/terraform-google-bootstrap module.
//
// The Bootstrap component handles:
//   - Seed project creation (with lien + default SA management)
//   - KMS key ring and crypto key for state encryption
//   - GCS state bucket with KMS encryption and versioning
//   - Org policy for cross-project SA usage
//   - State bucket IAM grants
func deploySeedProject(ctx *pulumi.Context, cfg *Config, folderID pulumi.StringOutput, bucketIAMMembers []pulumi.StringInput, grant *metadataGrant) (*SeedProject, error) {
	kmsPrevent := !cfg.BucketTFStateKMSForceDestroy
	// Deterministic path: gate the label UPDATE behind the IAM-propagation wait by
	// deriving a label VALUE from the gate. This is the only way to make the inner
	// organizations.Project (created two component layers deep) wait for the grant;
	// a component-level DependsOn would not reach it.
	var seedBusinessCode pulumi.StringInput = pulumi.String("shared")
	if grant != nil && grant.Active {
		seedBusinessCode = gatedLabel(grant.Gate, "shared")
	}
	b, err := bootstrap.NewBootstrap(ctx, "seed-bootstrap", &bootstrap.BootstrapArgs{
		OrgID:            cfg.OrgID,
		FolderID:         folderID,
		BillingAccount:   cfg.BillingAccount,
		ProjectPrefix:    cfg.ProjectPrefix,
		DefaultRegion:    cfg.DefaultRegion,
		DefaultRegionKMS: cfg.DefaultRegionKMS,
		DefaultRegionGCS: cfg.DefaultRegionGCS,
		RandomSuffix:     cfg.RandomSuffix,
		ProjectLabels: pulumi.StringMap{
			"environment":       pulumi.String("bootstrap"),
			"application_name":  pulumi.String("seed-bootstrap"),
			"billing_code":      pulumi.String("1234"),
			"primary_contact":   pulumi.String("james_nguyen"),
			"secondary_contact": pulumi.String("christine_kim"),
			"business_code":     seedBusinessCode,
			"env_code":          pulumi.String("b"),
			"vpc":               pulumi.String("none"),
		},
		ActivateApis: []string{
			"serviceusage.googleapis.com",
			"servicenetworking.googleapis.com",
			"cloudkms.googleapis.com",
			"compute.googleapis.com",
			"logging.googleapis.com",
			"bigquery.googleapis.com",
			"cloudresourcemanager.googleapis.com",
			"cloudbilling.googleapis.com",
			"cloudbuild.googleapis.com",
			"iam.googleapis.com",
			"admin.googleapis.com",
			"appengine.googleapis.com",
			"storage-api.googleapis.com",
			"monitoring.googleapis.com",
			"pubsub.googleapis.com",
			"securitycenter.googleapis.com",
			"accesscontextmanager.googleapis.com",
			"billingbudgets.googleapis.com",
			"essentialcontacts.googleapis.com",
			"assuredworkloads.googleapis.com",
			"cloudasset.googleapis.com",
			"orgpolicy.googleapis.com",
		},

		// State Bucket
		BucketPrefix:       cfg.BucketPrefix,
		BucketForceDestroy: cfg.BucketForceDestroy,

		// KMS — matches TF foundation defaults
		KeyProtectionLevel: cfg.KMSKeyProtectionLevel,
		KMSPreventDestroy:  &kmsPrevent,

		// State bucket IAM — grant access to all pipeline SAs and org admins
		StateBucketIAMMembers: bucketIAMMembers,

		// Inject Service Usage Admin for the pipeline SAs before APIs are enabled.
		SAExecutors: []string{"sa-terraform-bootstrap"},
	}, pulumi.Protect(true))
	if err != nil {
		return nil, err
	}

	// Create a separate state bucket for the 4-projects stage.
	// This isolates projects state from the main foundation state bucket.
	// Mirrors: module "gcp_projects_state_bucket" in build_github.tf.example
	projectsBucketName := b.SeedProjectID.ApplyT(func(id string) string {
		return fmt.Sprintf("%s-%s-gcp-projects-tfstate", cfg.BucketPrefix, id)
	}).(pulumi.StringOutput)

	enabled := true
	projectsStateBucket, err := libstorage.NewSimpleBucket(ctx, "projects-state-bucket", &libstorage.SimpleBucketArgs{
		Name:         projectsBucketName,
		ProjectID:    b.SeedProjectID,
		Location:     pulumi.String(cfg.DefaultRegionGCS),
		ForceDestroy: pulumi.Bool(cfg.BucketForceDestroy),
		Versioning:   &enabled,
		Encryption: &storage.BucketEncryptionArgs{
			DefaultKmsKeyName: b.KMSKeyID,
		},
	}, pulumi.DependsOn([]pulumi.Resource{b}))
	if err != nil {
		return nil, err
	}

	return &SeedProject{
		ProjectID:               b.SeedProjectID,
		StateBucketName:         b.StateBucketName,
		ProjectsStateBucketName: projectsStateBucket.Bucket.Name,
		KMSKeyID:                b.KMSKeyID,
		APIsReady:               b.SeedProject.ApisReady,
	}, nil
}

// deployCICDProject creates the CI/CD project that hosts the pipeline
// infrastructure (Artifact Registry, Cloud Build, Workload Identity, etc.).
// This is the equivalent of prj-b-cicd in the Terraform foundation.
// The CI/CD project uses pkg/project directly (not pkg/bootstrap) because
// it doesn't need state bucket or KMS — those live in the seed project.
func deployCICDProject(ctx *pulumi.Context, cfg *Config, folderID pulumi.StringOutput, grant *metadataGrant) (*CICDProject, error) {
	var cicdBusinessCode pulumi.StringInput = pulumi.String("shared")
	if grant != nil && grant.Active {
		cicdBusinessCode = gatedLabel(grant.Gate, "shared")
	}
	cicd, err := project.NewProject(ctx, "cicd-project", &project.ProjectArgs{
		ProjectID:             pulumi.String(fmt.Sprintf("%s-b-cicd", cfg.ProjectPrefix)),
		Name:                  pulumi.String(fmt.Sprintf("%s-b-cicd", cfg.ProjectPrefix)),
		FolderID:              folderID,
		BillingAccount:        pulumi.String(cfg.BillingAccount),
		RandomProjectID:       cfg.RandomSuffix,
		DeletionPolicy:        pulumi.String(cfg.ProjectDeletionPolicy),
		DefaultServiceAccount: "disable",
		Labels: pulumi.StringMap{
			"environment":       pulumi.String("bootstrap"),
			"application_name":  pulumi.String("cloudbuild-bootstrap"),
			"billing_code":      pulumi.String("1234"),
			"primary_contact":   pulumi.String("james_nguyen"),
			"secondary_contact": pulumi.String("christine_kim"),
			"business_code":     cicdBusinessCode,
			"env_code":          pulumi.String("b"),
			"vpc":               pulumi.String("none"),
		},
		ActivateApis: []string{
			"serviceusage.googleapis.com",
			"servicenetworking.googleapis.com",
			"compute.googleapis.com",
			"logging.googleapis.com",
			"iam.googleapis.com",
			"iamcredentials.googleapis.com",
			"admin.googleapis.com",
			"artifactregistry.googleapis.com",
			"cloudbuild.googleapis.com",
			"cloudresourcemanager.googleapis.com",
			"cloudbilling.googleapis.com",
			"appengine.googleapis.com",
			"storage-api.googleapis.com",
			"billingbudgets.googleapis.com",
			"bigquery.googleapis.com",
			"dns.googleapis.com",
			"workflows.googleapis.com",
			"cloudscheduler.googleapis.com",
		},
	}, pulumi.Protect(true))
	if err != nil {
		return nil, err
	}

	return &CICDProject{
		ProjectID: cicd.Project.ProjectId,
	}, nil
}
