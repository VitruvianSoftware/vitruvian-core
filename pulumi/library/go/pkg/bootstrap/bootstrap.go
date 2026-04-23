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

// Package bootstrap provides a reusable component for creating the seed
// infrastructure required by a GCP foundation. This mirrors the upstream
// terraform-google-modules/terraform-google-bootstrap module and bundles:
//
//   - Seed project (via pkg/project with lien + default SA management)
//   - KMS key ring and crypto key for state encryption
//   - GCS state bucket with KMS encryption and versioning
//   - Org policy to allow cross-project SA usage on the seed project
//   - State bucket IAM grants for service accounts and admin groups
//
// Foundation-specific resources (granular SAs, per-stage IAM bindings, CI/CD
// project) are NOT part of this module — they belong in the consuming
// foundation stage (0-bootstrap).
package bootstrap

import (
	"fmt"

	"github.com/VitruvianSoftware/pulumi-library/go/pkg/project"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/kms"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/projects"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/storage"
	"github.com/pulumi/pulumi-random/sdk/v4/go/random"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// BootstrapArgs configures the Bootstrap component.
// This mirrors the variables from terraform-google-modules/terraform-google-bootstrap.
type BootstrapArgs struct {
	// OrgID is the GCP organization ID. Required.
	OrgID string
	// FolderID is the folder under which the seed project is created.
	FolderID pulumi.StringInput
	// BillingAccount is the billing account to associate with the seed project.
	BillingAccount string
	// ProjectPrefix is the name prefix for the seed project (e.g. "prj").
	// The seed project ID will be "{ProjectPrefix}-b-seed".
	ProjectPrefix string

	// DefaultRegion is the region for KMS and GCS resources.
	DefaultRegion string
	// ProjectLabels are labels applied to the seed project.
	ProjectLabels pulumi.StringMapInput
	// ActivateApis is the list of APIs to enable on the seed project.
	ActivateApis []string

	// RandomSuffix appends a 4-char random hex suffix to project ID and bucket name.
	RandomSuffix bool
	// DeletionPolicy for the seed project. Defaults to "PREVENT".
	DeletionPolicy string
	// DefaultServiceAccount controls the default SA. Defaults to "disable".
	DefaultServiceAccount string

	// State Bucket
	// BucketPrefix is prepended to the bucket name (e.g. "bkt").
	BucketPrefix string
	// StateBucketName overrides the auto-generated bucket name.
	StateBucketName string
	// BucketForceDestroy allows bucket deletion even with objects.
	BucketForceDestroy bool
	// BucketLabels are labels for the state bucket.
	BucketLabels pulumi.StringMapInput

	// KMS
	// EncryptStateBucket enables KMS encryption for the state bucket.
	// Defaults to true, matching the TF foundation.
	EncryptStateBucket *bool
	// KeyRotationPeriod in seconds. Defaults to "7776000s" (90 days).
	KeyRotationPeriod string
	// KeyProtectionLevel is "SOFTWARE" or "HSM". Defaults to "SOFTWARE".
	KeyProtectionLevel string
	// KMSPreventDestroy prevents accidental KMS key deletion.
	KMSPreventDestroy *bool

	// StateBucketIAMMembers is a list of IAM members (e.g. "serviceAccount:...",
	// "group:...") to grant roles/storage.admin on the state bucket.
	// This allows the foundation SAs and admin groups to access the state.
	StateBucketIAMMembers []pulumi.StringInput
}

// Bootstrap is a Pulumi component that creates the seed infrastructure.
type Bootstrap struct {
	pulumi.ResourceState

	// SeedProject is the underlying project component.
	SeedProject *project.Project
	// SeedProjectID is the seed project's project ID.
	SeedProjectID pulumi.StringOutput
	// StateBucketName is the name of the GCS state bucket.
	StateBucketName pulumi.StringOutput
	// KMSKeyID is the fully qualified ID of the KMS crypto key.
	KMSKeyID pulumi.StringOutput
	// KMSKeyRingID is the fully qualified ID of the KMS key ring.
	KMSKeyRingID pulumi.StringOutput
}

// NewBootstrap creates the seed project, KMS, state bucket, org policy, and
// bucket IAM. This mirrors terraform-google-modules/terraform-google-bootstrap.
func NewBootstrap(ctx *pulumi.Context, name string, args *BootstrapArgs, opts ...pulumi.ResourceOption) (*Bootstrap, error) {
	component := &Bootstrap{}
	err := ctx.RegisterComponentResource("pkg:index:Bootstrap", name, component, opts...)
	if err != nil {
		return nil, err
	}

	// Apply defaults matching TF bootstrap module
	deletionPolicy := args.DeletionPolicy
	if deletionPolicy == "" {
		deletionPolicy = "PREVENT"
	}
	defaultSA := args.DefaultServiceAccount
	if defaultSA == "" {
		defaultSA = "disable"
	}
	encryptBucket := true
	if args.EncryptStateBucket != nil {
		encryptBucket = *args.EncryptStateBucket
	}
	keyRotation := args.KeyRotationPeriod
	if keyRotation == "" {
		keyRotation = "7776000s" // 90 days
	}
	keyProtection := args.KeyProtectionLevel
	if keyProtection == "" {
		keyProtection = "SOFTWARE"
	}
	kmsPreventDestroy := true
	if args.KMSPreventDestroy != nil {
		kmsPreventDestroy = *args.KMSPreventDestroy
	}

	// Ensure cloudkms.googleapis.com is activated if encrypting the bucket
	activateApis := args.ActivateApis
	if encryptBucket {
		activateApis = appendIfMissing(activateApis, "cloudkms.googleapis.com")
	}

	// ========================================================================
	// 1. Seed Project
	// Created via pkg/project with lien and default SA management.
	// Matches: module "seed_project" in TF bootstrap main.tf
	// ========================================================================
	seed, err := project.NewProject(ctx, fmt.Sprintf("%s-seed", name), &project.ProjectArgs{
		ProjectID:             pulumi.String(fmt.Sprintf("%s-b-seed", args.ProjectPrefix)),
		Name:                  pulumi.String(fmt.Sprintf("%s-b-seed", args.ProjectPrefix)),
		FolderID:              args.FolderID,
		BillingAccount:        pulumi.String(args.BillingAccount),
		RandomProjectID:       args.RandomSuffix,
		DeletionPolicy:        pulumi.String(deletionPolicy),
		Labels:                args.ProjectLabels,
		ActivateApis:          activateApis,
		Lien:                  true, // Always lien the seed project
		DefaultServiceAccount: defaultSA,
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.SeedProject = seed
	component.SeedProjectID = seed.Project.ProjectId

	// ========================================================================
	// 2. Org Policy — disable cross-project SA usage constraint
	// Matches: module "enable_cross_project_service_account_usage" in TF
	// This allows the seed project's SAs to operate across projects.
	// ========================================================================
	if _, err := projects.NewOrganizationPolicy(ctx, fmt.Sprintf("%s-cross-project-sa", name), &projects.OrganizationPolicyArgs{
		Project:    seed.Project.ProjectId,
		Constraint: pulumi.String("iam.disableCrossProjectServiceAccountUsage"),
		BooleanPolicy: &projects.OrganizationPolicyBooleanPolicyArgs{
			Enforced: pulumi.Bool(false),
		},
	}, pulumi.Parent(component)); err != nil {
		return nil, err
	}

	// ========================================================================
	// 3. KMS Key Ring + Crypto Key
	// Matches: module "kms" in TF bootstrap main.tf
	// ========================================================================
	var cryptoKeyID pulumi.StringOutput
	var keyRingID pulumi.StringOutput

	if encryptBucket {
		keyRing, err := kms.NewKeyRing(ctx, fmt.Sprintf("%s-keyring", name), &kms.KeyRingArgs{
			Project:  seed.Project.ProjectId,
			Name:     pulumi.String(fmt.Sprintf("%s-keyring", args.ProjectPrefix)),
			Location: pulumi.String(args.DefaultRegion),
		}, pulumi.Parent(component), pulumi.Protect(kmsPreventDestroy))
		if err != nil {
			return nil, err
		}
		keyRingID = keyRing.ID().ApplyT(func(id pulumi.ID) string {
			return string(id)
		}).(pulumi.StringOutput)

		cryptoKey, err := kms.NewCryptoKey(ctx, fmt.Sprintf("%s-key", name), &kms.CryptoKeyArgs{
			Name:           pulumi.String(fmt.Sprintf("%s-key", args.ProjectPrefix)),
			KeyRing:        keyRing.ID(),
			RotationPeriod: pulumi.String(keyRotation),
			VersionTemplate: &kms.CryptoKeyVersionTemplateArgs{
				ProtectionLevel: pulumi.String(keyProtection),
				Algorithm:       pulumi.String("GOOGLE_SYMMETRIC_ENCRYPTION"),
			},
		}, pulumi.Parent(component), pulumi.Protect(kmsPreventDestroy))
		if err != nil {
			return nil, err
		}
		cryptoKeyID = cryptoKey.ID().ApplyT(func(id pulumi.ID) string {
			return string(id)
		}).(pulumi.StringOutput)
	}

	component.KMSKeyID = cryptoKeyID
	component.KMSKeyRingID = keyRingID

	// ========================================================================
	// 4. State Bucket
	// Matches: google_storage_bucket "org_terraform_state" in TF bootstrap
	// ========================================================================
	stateBucketName, err := resolveStateBucketName(ctx, name, args)
	if err != nil {
		return nil, err
	}

	bucketArgs := &storage.BucketArgs{
		Project:                  seed.Project.ProjectId,
		Name:                     stateBucketName,
		Location:                 pulumi.String(args.DefaultRegion),
		UniformBucketLevelAccess: pulumi.Bool(true),
		ForceDestroy:             pulumi.Bool(args.BucketForceDestroy),
		Labels:                   args.BucketLabels,
		Versioning: &storage.BucketVersioningArgs{
			Enabled: pulumi.Bool(true),
		},
	}
	if encryptBucket {
		bucketArgs.Encryption = &storage.BucketEncryptionArgs{
			DefaultKmsKeyName: cryptoKeyID,
		}
	}

	stateBucket, err := storage.NewBucket(ctx, fmt.Sprintf("%s-state-bucket", name), bucketArgs, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.StateBucketName = stateBucket.Name

	// ========================================================================
	// 5. State Bucket IAM
	// Matches: google_storage_bucket_iam_member resources in TF bootstrap
	// Grants storage.admin to each provided SA/group.
	// ========================================================================
	for i, member := range args.StateBucketIAMMembers {
		if _, err := storage.NewBucketIAMMember(ctx, fmt.Sprintf("%s-bucket-iam-%d", name, i), &storage.BucketIAMMemberArgs{
			Bucket: stateBucket.Name,
			Role:   pulumi.String("roles/storage.admin"),
			Member: member,
		}, pulumi.Parent(component)); err != nil {
			return nil, err
		}
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{
		"seedProjectId":   seed.Project.ProjectId,
		"stateBucketName": stateBucket.Name,
	})

	return component, nil
}

// resolveStateBucketName generates the state bucket name, optionally with a
// random suffix. Matches the TF bootstrap module's bucket naming logic.
func resolveStateBucketName(ctx *pulumi.Context, name string, args *BootstrapArgs) (pulumi.StringInput, error) {
	baseName := args.StateBucketName
	if baseName == "" {
		if args.BucketPrefix != "" {
			baseName = fmt.Sprintf("%s-%s-b-seed-tfstate", args.BucketPrefix, args.ProjectPrefix)
		} else {
			baseName = fmt.Sprintf("%s-b-seed-tfstate", args.ProjectPrefix)
		}
	}

	if args.RandomSuffix {
		suffix, err := random.NewRandomId(ctx, fmt.Sprintf("%s-bucket-suffix", name), &random.RandomIdArgs{
			ByteLength: pulumi.Int(2),
		})
		if err != nil {
			return nil, err
		}
		return pulumi.Sprintf("%s-%s", baseName, suffix.Hex), nil
	}
	return pulumi.String(baseName), nil
}

// appendIfMissing appends s to the slice if it's not already present.
func appendIfMissing(slice []string, s string) []string {
	for _, item := range slice {
		if item == s {
			return slice
		}
	}
	return append(slice, s)
}
