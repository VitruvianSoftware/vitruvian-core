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

// Package security provides reusable Pulumi components for GCP security
// infrastructure. Components in this package mirror local modules from the
// upstream Google Terraform Example Foundation's 1-org phase.
//
// Components:
//
//   - CAIMonitoring: Mirrors terraform-example-foundation/1-org/modules/cai-monitoring.
//     Deploys a Cloud Asset Inventory monitoring pipeline that watches for
//     privileged IAM role grants across an organization and reports violations
//     as Security Command Center findings.
package security

import (
	"fmt"
	"strings"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/artifactregistry"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/cloudasset"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/cloudfunctionsv2"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/organizations"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/projects"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/pubsub"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/securitycenter"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/storage"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// DefaultRolesToMonitor is the default set of IAM roles that trigger SCC
// findings when granted to any principal. Matches the upstream Terraform
// module's roles_to_monitor variable default.
var DefaultRolesToMonitor = []string{
	"roles/owner",
	"roles/editor",
	"roles/resourcemanager.organizationAdmin",
	"roles/compute.networkAdmin",
	"roles/compute.orgFirewallPolicyAdmin",
}

// CAIMonitoringArgs configures the Cloud Asset Inventory monitoring component.
// Mirrors the upstream Terraform module's variables.tf interface.
type CAIMonitoringArgs struct {
	// OrgID is the GCP Organization ID to monitor. Required.
	OrgID pulumi.StringInput

	// ProjectID is the GCP project where monitoring resources are created. Required.
	ProjectID pulumi.StringInput

	// Location is the GCP region for Cloud Function and Artifact Registry.
	// Defaults to "us-central1" to match upstream.
	Location string

	// BuildServiceAccount is the fully-qualified name of the service account
	// used by Cloud Build to build the Cloud Function container. Required.
	// Format: "projects/<project>/serviceAccounts/<email>"
	BuildServiceAccount pulumi.StringInput

	// FunctionSourcePath is the local filesystem path to the Cloud Function
	// source directory (containing index.js, package.json). Required.
	// The directory is archived and uploaded to Cloud Storage.
	FunctionSourcePath string

	// RolesToMonitor is the list of IAM roles that trigger SCC findings when
	// granted to any member. Defaults to DefaultRolesToMonitor.
	RolesToMonitor []string

	// EncryptionKey is the KMS key resource name for CMEK encryption of
	// Artifact Registry, Cloud Storage, and Pub/Sub. Leave empty to skip CMEK.
	EncryptionKey string

	// Labels applied to supporting resources (Artifact Registry, Cloud Function).
	Labels map[string]string
}

// CAIMonitoring is a Pulumi component that deploys the complete Cloud Asset
// Inventory monitoring pipeline. It mirrors the upstream Terraform foundation's
// 1-org/modules/cai-monitoring module.
//
// The pipeline works as follows:
//  1. A Cloud Asset Organization Feed watches for IAM_POLICY changes
//  2. Changes are published to a Pub/Sub topic
//  3. A Cloud Function v2 is triggered by the Pub/Sub messages
//  4. The function checks for grants of monitored privileged roles
//  5. Violations are reported as SCC findings via a custom SCC Source
//
// Resources created:
//   - Service account for the Cloud Function (cai-monitoring)
//   - Org-level IAM: roles/securitycenter.findingsEditor
//   - Project-level IAM: pubsub.publisher, eventarc.eventReceiver, run.invoker
//   - Service identities for cloudfunctions, artifactregistry, pubsub
//   - Artifact Registry repository for function container image
//   - Cloud Storage bucket + object for function source code
//   - Pub/Sub topic for CAI feed events
//   - Cloud Asset Organization Feed (IAM_POLICY content type)
//   - SCC v2 Organization Source for findings
//   - Cloud Function v2 (Node.js 20) triggered by Pub/Sub
type CAIMonitoring struct {
	pulumi.ResourceState

	// ArtifactRegistryName is the name of the AR repository created.
	ArtifactRegistryName pulumi.StringOutput `pulumi:"artifactRegistryName"`

	// BucketName is the name of the source code storage bucket.
	BucketName pulumi.StringOutput `pulumi:"bucketName"`

	// AssetFeedName is the name of the Cloud Asset Organization Feed.
	AssetFeedName pulumi.StringOutput `pulumi:"assetFeedName"`

	// TopicName is the name of the Pub/Sub topic.
	TopicName pulumi.StringOutput `pulumi:"topicName"`

	// SCCSourceName is the name of the SCC v2 Organization Source.
	SCCSourceName pulumi.StringOutput `pulumi:"sccSourceName"`
}

// NewCAIMonitoring creates a new CAI monitoring pipeline component.
// See CAIMonitoringArgs and CAIMonitoring for full documentation.
func NewCAIMonitoring(ctx *pulumi.Context, name string, args *CAIMonitoringArgs, opts ...pulumi.ResourceOption) (*CAIMonitoring, error) {
	if args == nil {
		return nil, fmt.Errorf("args cannot be nil")
	}

	comp := &CAIMonitoring{}
	err := ctx.RegisterComponentResource("vitruvian:security:CAIMonitoring", name, comp, opts...)
	if err != nil {
		return nil, err
	}

	parent := pulumi.Parent(comp)

	// Apply defaults
	location := args.Location
	if location == "" {
		location = "us-central1"
	}
	rolesToMonitor := args.RolesToMonitor
	if len(rolesToMonitor) == 0 {
		rolesToMonitor = DefaultRolesToMonitor
	}

	// ====================================================================
	// 1. Cloud Function Service Account
	// Mirrors: google_service_account "cloudfunction" in iam.tf
	// ====================================================================
	caiSA, err := serviceaccount.NewAccount(ctx, name+"-sa", &serviceaccount.AccountArgs{
		Project:     args.ProjectID,
		AccountId:   pulumi.String("cai-monitoring"),
		Description: pulumi.String("Service account for CAI monitoring Cloud Function"),
	}, parent)
	if err != nil {
		return nil, err
	}

	caiSAMember := caiSA.Email.ApplyT(func(email string) string {
		return fmt.Sprintf("serviceAccount:%s", email)
	}).(pulumi.StringOutput)

	// Org-level: SCC findings editor
	// Mirrors: google_organization_iam_member "cloudfunction_findings_editor"
	findingsEditorIAM, err := organizations.NewIAMMember(ctx, name+"-sa-findings-editor", &organizations.IAMMemberArgs{
		OrgId:  args.OrgID,
		Role:   pulumi.String("roles/securitycenter.findingsEditor"),
		Member: caiSAMember,
	}, parent)
	if err != nil {
		return nil, err
	}

	// Project-level: roles for Pub/Sub, Eventarc, and Cloud Run
	// Mirrors: google_project_iam_member "cloudfunction_iam" for_each
	var iamDeps []pulumi.Resource
	cfRoles := []string{
		"roles/pubsub.publisher",
		"roles/eventarc.eventReceiver",
		"roles/run.invoker",
	}
	for _, role := range cfRoles {
		iam, err := projects.NewIAMMember(ctx, fmt.Sprintf("%s-sa-%s", name, role), &projects.IAMMemberArgs{
			Project: args.ProjectID,
			Role:    pulumi.String(role),
			Member:  caiSAMember,
		}, parent)
		if err != nil {
			return nil, err
		}
		iamDeps = append(iamDeps, iam)
	}
	iamDeps = append(iamDeps, findingsEditorIAM)

	// ====================================================================
	// 2. Service Identities
	// Mirrors: google_project_service_identity "service_sa" for_each
	// ====================================================================
	caiServices := []string{
		"cloudfunctions.googleapis.com",
		"artifactregistry.googleapis.com",
		"pubsub.googleapis.com",
	}
	for _, svc := range caiServices {
		if _, err := projects.NewServiceIdentity(ctx, fmt.Sprintf("%s-identity-%s", name, svc), &projects.ServiceIdentityArgs{
			Project: args.ProjectID,
			Service: pulumi.String(svc),
		}, parent); err != nil {
			return nil, err
		}
	}

	// ====================================================================
	// 3. Artifact Registry Repository
	// Mirrors: google_artifact_registry_repository "cloudfunction"
	// ====================================================================
	arArgs := &artifactregistry.RepositoryArgs{
		Project:      args.ProjectID,
		Location:     pulumi.String(location),
		RepositoryId: pulumi.String("ar-cai-monitoring"),
		Description:  pulumi.String("Container images for the CAI monitoring Cloud Function"),
		Format:       pulumi.String("DOCKER"),
	}
	if args.EncryptionKey != "" {
		arArgs.KmsKeyName = pulumi.StringPtr(args.EncryptionKey)
	}

	arRepo, err := artifactregistry.NewRepository(ctx, name+"-ar", arArgs,
		parent, pulumi.DependsOn(iamDeps))
	if err != nil {
		return nil, err
	}

	// ====================================================================
	// 4. Cloud Storage Bucket + Source Code Upload
	// Mirrors: module "cloudfunction_source_bucket" + google_storage_bucket_object
	// ====================================================================
	sourceBucket, err := storage.NewBucket(ctx, name+"-source-bucket", &storage.BucketArgs{
		Project: args.ProjectID,
		Name: args.ProjectID.(pulumi.StringInput).ToStringOutput().ApplyT(func(id string) string {
			return fmt.Sprintf("bkt-cai-monitoring-sources-%s", id)
		}).(pulumi.StringOutput),
		Location:                 pulumi.String(location),
		ForceDestroy:             pulumi.Bool(true),
		UniformBucketLevelAccess: pulumi.Bool(true),
	}, parent, pulumi.DependsOn(iamDeps))
	if err != nil {
		return nil, err
	}

	sourceObject, err := storage.NewBucketObject(ctx, name+"-source-zip", &storage.BucketObjectArgs{
		Bucket: sourceBucket.Name,
		Name:   pulumi.String("cai-monitoring-function.zip"),
		Source: pulumi.NewFileArchive(args.FunctionSourcePath),
	}, parent)
	if err != nil {
		return nil, err
	}

	// ====================================================================
	// 5. Pub/Sub Topic + Cloud Asset Organization Feed
	// Mirrors: module "pubsub_cai_feed" + google_cloud_asset_organization_feed
	// ====================================================================
	caiTopic, err := pubsub.NewTopic(ctx, name+"-topic", &pubsub.TopicArgs{
		Project: args.ProjectID,
		Name:    pulumi.String("top-cai-monitoring-event"),
	}, parent, pulumi.DependsOn(iamDeps))
	if err != nil {
		return nil, err
	}

	caiFeed, err := cloudasset.NewOrganizationFeed(ctx, name+"-org-feed", &cloudasset.OrganizationFeedArgs{
		FeedId:         pulumi.String("fd-cai-monitoring"),
		BillingProject: args.ProjectID,
		OrgId:          args.OrgID,
		ContentType:    pulumi.String("IAM_POLICY"),
		AssetTypes:     pulumi.StringArray{pulumi.String(".*")},
		FeedOutputConfig: &cloudasset.OrganizationFeedFeedOutputConfigArgs{
			PubsubDestination: &cloudasset.OrganizationFeedFeedOutputConfigPubsubDestinationArgs{
				Topic: caiTopic.ID(),
			},
		},
	}, parent)
	if err != nil {
		return nil, err
	}

	// ====================================================================
	// 6. SCC v2 Organization Source
	// Mirrors: google_scc_v2_organization_source "cai_monitoring"
	// ====================================================================
	sccSource, err := securitycenter.NewV2OrganizationSource(ctx, name+"-scc-source", &securitycenter.V2OrganizationSourceArgs{
		Organization: args.OrgID,
		DisplayName:  pulumi.String("CAI Monitoring"),
		Description:  pulumi.String("SCC Finding Source for caiMonitoring Cloud Functions."),
	}, parent)
	if err != nil {
		return nil, err
	}

	// ====================================================================
	// 7. Cloud Function v2
	// Mirrors: module "cloud_function" (GoogleCloudPlatform/cloud-functions)
	// ====================================================================
	rolesEnvVar := strings.Join(rolesToMonitor, ",")

	if _, err := cloudfunctionsv2.NewFunction(ctx, name+"-function", &cloudfunctionsv2.FunctionArgs{
		Project:     args.ProjectID,
		Location:    pulumi.String(location),
		Name:        pulumi.String("caiMonitoring"),
		Description: pulumi.String("Check on the Organization for members (users, groups and service accounts) that contains the IAM roles listed."),
		BuildConfig: &cloudfunctionsv2.FunctionBuildConfigArgs{
			Runtime:    pulumi.String("nodejs20"),
			EntryPoint: pulumi.String("caiMonitoring"),
			Source: &cloudfunctionsv2.FunctionBuildConfigSourceArgs{
				StorageSource: &cloudfunctionsv2.FunctionBuildConfigSourceStorageSourceArgs{
					Bucket: sourceBucket.Name,
					Object: sourceObject.Name,
				},
			},
			DockerRepository: arRepo.ID(),
			ServiceAccount:   args.BuildServiceAccount,
		},
		ServiceConfig: &cloudfunctionsv2.FunctionServiceConfigArgs{
			ServiceAccountEmail: caiSA.Email,
			EnvironmentVariables: pulumi.StringMap{
				"ROLES":     pulumi.String(rolesEnvVar),
				"SOURCE_ID": sccSource.Name,
			},
		},
		EventTrigger: &cloudfunctionsv2.FunctionEventTriggerArgs{
			TriggerRegion:       pulumi.String(location),
			EventType:           pulumi.String("google.cloud.pubsub.topic.v1.messagePublished"),
			PubsubTopic:         caiTopic.ID(),
			RetryPolicy:         pulumi.String("RETRY_POLICY_RETRY"),
			ServiceAccountEmail: caiSA.Email,
		},
	}, parent, pulumi.DependsOn(iamDeps)); err != nil {
		return nil, err
	}

	// ====================================================================
	// Wire outputs
	// ====================================================================
	comp.ArtifactRegistryName = arRepo.Name
	comp.BucketName = sourceBucket.Name
	comp.AssetFeedName = caiFeed.Name
	comp.TopicName = caiTopic.Name
	comp.SCCSourceName = sccSource.Name

	if err := ctx.RegisterResourceOutputs(comp, pulumi.Map{
		"artifactRegistryName": arRepo.Name,
		"bucketName":           sourceBucket.Name,
		"assetFeedName":        caiFeed.Name,
		"topicName":            caiTopic.Name,
		"sccSourceName":        sccSource.Name,
	}); err != nil {
		return nil, err
	}

	return comp, nil
}
