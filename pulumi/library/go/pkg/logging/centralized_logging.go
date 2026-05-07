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

package logging

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/logging"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/projects"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/pubsub"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/storage"
	"github.com/pulumi/pulumi-random/sdk/v4/go/random"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// StorageOptions configures the Cloud Storage log export destination.
// Mirrors the upstream centralized-logging module's storage_options variable.
type StorageOptions struct {
	// LoggingSinkName overrides the default sink name. If empty, a default
	// name is generated.
	LoggingSinkName string

	// LoggingSinkFilter is the log filter expression applied to this sink.
	LoggingSinkFilter string

	// StorageBucketName overrides the auto-generated bucket name.
	StorageBucketName string

	// Location is the GCS bucket location (e.g. "US", "us-central1").
	Location string

	// RetentionPolicyEnabled enables a data retention policy on the bucket.
	RetentionPolicyEnabled bool

	// RetentionPolicyIsLocked when true, the retention policy cannot be
	// shortened or removed.
	RetentionPolicyIsLocked bool

	// RetentionPolicyPeriodDays is the retention period in days.
	RetentionPolicyPeriodDays int

	// Versioning enables object versioning on the bucket.
	Versioning bool

	// ForceDestroy allows Terraform/Pulumi to destroy a non-empty bucket.
	ForceDestroy bool
}

// PubSubOptions configures the Pub/Sub log export destination.
// Mirrors the upstream centralized-logging module's pubsub_options variable.
type PubSubOptions struct {
	// LoggingSinkName overrides the default sink name.
	LoggingSinkName string

	// LoggingSinkFilter is the log filter expression applied to this sink.
	LoggingSinkFilter string

	// TopicName overrides the auto-generated topic name.
	TopicName string

	// CreateSubscriber when true, creates a pull subscription for the topic.
	CreateSubscriber bool
}

// ProjectOptions configures the Logging project log bucket destination.
// Mirrors the upstream centralized-logging module's project_options variable.
type ProjectOptions struct {
	// LoggingSinkName overrides the default sink name.
	LoggingSinkName string

	// LoggingSinkFilter is the log filter expression applied to this sink.
	LoggingSinkFilter string

	// LogBucketID is the ID of the log bucket (default: "AggregatedLogs").
	LogBucketID string

	// LogBucketDescription is a description for the log bucket.
	LogBucketDescription string

	// Location is the log bucket location (e.g. "us-central1", "global").
	Location string

	// EnableAnalytics enables Log Analytics on the bucket.
	EnableAnalytics bool

	// LinkedDatasetID is the BigQuery dataset ID linked to the log bucket.
	LinkedDatasetID string

	// LinkedDatasetDescription is a description for the linked dataset.
	LinkedDatasetDescription string
}

// CentralizedLoggingArgs configures the CentralizedLogging component.
// This mirrors the upstream centralized-logging module's interface:
// resources × destinations, with optional billing account sinks.
type CentralizedLoggingArgs struct {
	// Resources is a map of resource IDs to export logs from.
	// In the standard foundation, this is typically:
	//   {"resource": "<org_id or folder_id>"}
	Resources map[string]string

	// ResourceType must be "organization" or "folder".
	ResourceType string

	// LoggingDestinationProjectID is the project that hosts all log
	// destinations (storage bucket, pub/sub topic, log bucket).
	LoggingDestinationProjectID pulumi.StringInput

	// BillingAccount is the billing account ID. Required when
	// EnableBillingAccountSink is true.
	BillingAccount string

	// EnableBillingAccountSink when true, creates billing account sinks
	// to all configured destinations.
	EnableBillingAccountSink bool

	// StorageOptions configures the Cloud Storage destination.
	// Nil means no storage sink is created.
	StorageOptions *StorageOptions

	// PubSubOptions configures the Pub/Sub destination.
	// Nil means no pub/sub sink is created.
	PubSubOptions *PubSubOptions

	// ProjectOptions configures the Logging project bucket destination.
	// Nil means no project sink is created.
	ProjectOptions *ProjectOptions
}

// CentralizedLoggingOutputs holds output references from the component.
type CentralizedLoggingOutputs struct {
	// StorageBucketName is the name of the log storage bucket (if created).
	StorageBucketName pulumi.StringOutput

	// PubSubTopicName is the name of the log Pub/Sub topic (if created).
	PubSubTopicName pulumi.StringOutput

	// ProjectLogBucketName is the resource name of the log bucket (if created).
	ProjectLogBucketName pulumi.StringOutput

	// LinkedDatasetName is the resource name of the linked BQ dataset (if created).
	LinkedDatasetName pulumi.StringOutput

	// BillingSinkNames is a map of destination key → billing sink name.
	// Mirrors TF centralized-logging module's billing_sink_names output.
	BillingSinkNames map[string]pulumi.StringOutput

	// LastResource is the last resource created, for dependency ordering.
	LastResource pulumi.Resource
}

// CentralizedLogging is a component that creates a complete centralized
// logging infrastructure with org/folder sinks exporting to Storage,
// Pub/Sub, and a Logging project bucket.
type CentralizedLogging struct {
	pulumi.ResourceState
	CentralizedLoggingOutputs
}

// NewCentralizedLogging creates a centralized logging infrastructure.
//
// It mirrors the upstream Terraform foundation's modules/centralized-logging
// module, creating:
//   - Destination resources (storage bucket, pub/sub topic, log bucket)
//   - Log sinks for each resource → destination combination
//   - Billing account sinks (when enabled)
//   - IAM grants for each sink writer identity on each destination
//   - An internal project sink to capture the logging project's own logs
func NewCentralizedLogging(ctx *pulumi.Context, name string, args *CentralizedLoggingArgs, opts ...pulumi.ResourceOption) (*CentralizedLogging, error) {
	if args == nil {
		return nil, fmt.Errorf("args cannot be nil")
	}
	if len(args.Resources) == 0 {
		return nil, fmt.Errorf("resources map must have at least 1 item")
	}

	component := &CentralizedLogging{}
	err := ctx.RegisterComponentResource("pkg:logging:CentralizedLogging", name, component, opts...)
	if err != nil {
		return nil, err
	}

	childOpts := []pulumi.ResourceOption{pulumi.Parent(component)}

	// Random suffix for globally unique names
	suffix, err := random.NewRandomString(ctx, name+"-suffix", &random.RandomStringArgs{
		Length:  pulumi.Int(4),
		Upper:   pulumi.Bool(false),
		Special: pulumi.Bool(false),
	}, childOpts...)
	if err != nil {
		return nil, err
	}

	var lastResource pulumi.Resource
	billingSinkNames := make(map[string]pulumi.StringOutput)

	// ====================================================================
	// Project log bucket destination
	// ====================================================================
	if args.ProjectOptions != nil {
		po := args.ProjectOptions
		bucketID := po.LogBucketID
		if bucketID == "" {
			bucketID = "AggregatedLogs"
		}
		location := po.Location
		if location == "" {
			location = "global"
		}

		logBucket, err := logging.NewProjectBucketConfig(ctx, name+"-logbucket", &logging.ProjectBucketConfigArgs{
			Project:         args.LoggingDestinationProjectID,
			Location:        pulumi.String(location),
			BucketId:        pulumi.String(bucketID),
			Description:     pulumi.String(po.LogBucketDescription),
			EnableAnalytics: pulumi.Bool(po.EnableAnalytics),
		}, childOpts...)
		if err != nil {
			return nil, err
		}
		component.ProjectLogBucketName = logBucket.ID().ApplyT(func(id string) string { return id }).(pulumi.StringOutput)

		// Linked BigQuery dataset for log analytics
		if po.LinkedDatasetID != "" {
			ld, err := logging.NewLinkedDataset(ctx, name+"-linked-dataset", &logging.LinkedDatasetArgs{
				Parent:      args.LoggingDestinationProjectID.ToStringOutput().ApplyT(func(id string) string { return "projects/" + id }).(pulumi.StringOutput),
				Bucket:      logBucket.ID(),
				LinkId:      pulumi.String(po.LinkedDatasetID),
				Location:    pulumi.String(location),
				Description: pulumi.String(po.LinkedDatasetDescription),
			}, childOpts...)
			if err != nil {
				return nil, err
			}
			component.LinkedDatasetName = ld.Name
		}

		// Create org/folder sinks → project log bucket
		sinkName := po.LoggingSinkName
		if sinkName == "" {
			sinkName = "sk-c-logging-prj"
		}
		for resKey, resID := range args.Resources {
			destURI := args.LoggingDestinationProjectID.ToStringOutput().ApplyT(func(projID string) string {
				return fmt.Sprintf("logging.googleapis.com/projects/%s/locations/%s/buckets/%s", projID, location, bucketID)
			}).(pulumi.StringOutput)

			sink, err := NewLogExport(ctx, fmt.Sprintf("%s-prj-%s", name, resKey), &LogExportArgs{
				DestinationURI:       destURI,
				Filter:               pulumi.String(po.LoggingSinkFilter),
				LogSinkName:          pulumi.String(sinkName),
				ParentResourceID:     pulumi.String(resID),
				ResourceType:         args.ResourceType,
				UniqueWriterIdentity: true,
				IncludeChildren:      true,
			}, childOpts...)
			if err != nil {
				return nil, err
			}

			// Grant writer identity logWriter on the destination project
			iamMember, err := projects.NewIAMMember(ctx, fmt.Sprintf("%s-prj-iam-%s", name, resKey), &projects.IAMMemberArgs{
				Project: args.LoggingDestinationProjectID,
				Role:    pulumi.String("roles/logging.logWriter"),
				Member:  sink.WriterIdentity,
			}, childOpts...)
			if err != nil {
				return nil, err
			}
			lastResource = iamMember
		}

		// Internal project-level sink: routes the logging project's own
		// logs into the AggregatedLogs bucket. Without this, the audit
		// project itself is a blind spot.
		internalDestURI := args.LoggingDestinationProjectID.ToStringOutput().ApplyT(func(projID string) string {
			return fmt.Sprintf("logging.googleapis.com/projects/%s/locations/%s/buckets/%s", projID, location, bucketID)
		}).(pulumi.StringOutput)

		internalSink, err := NewLogExport(ctx, name+"-internal-prj", &LogExportArgs{
			DestinationURI:       internalDestURI,
			Filter:               pulumi.String(po.LoggingSinkFilter),
			LogSinkName:          pulumi.String(sinkName + "-la"),
			ParentResourceID:     args.LoggingDestinationProjectID,
			ResourceType:         "project",
			UniqueWriterIdentity: true,
		}, childOpts...)
		if err != nil {
			return nil, err
		}
		lastResource = internalSink
	}

	// ====================================================================
	// Storage destination
	// ====================================================================
	if args.StorageOptions != nil {
		so := args.StorageOptions
		location := so.Location
		if location == "" {
			location = "US"
		}

		bucketName := pulumi.All(args.LoggingDestinationProjectID, suffix.Result).ApplyT(func(vals []interface{}) string {
			projID := vals[0].(string)
			s := vals[1].(string)
			if so.StorageBucketName != "" {
				return so.StorageBucketName
			}
			return fmt.Sprintf("bkt-logs-%s-%s", projID, s)
		}).(pulumi.StringOutput)

		bucketArgs := &storage.BucketArgs{
			Project:                  args.LoggingDestinationProjectID,
			Name:                     bucketName,
			Location:                 pulumi.String(location),
			UniformBucketLevelAccess: pulumi.Bool(true),
			ForceDestroy:             pulumi.Bool(so.ForceDestroy),
			Versioning: &storage.BucketVersioningArgs{
				Enabled: pulumi.Bool(so.Versioning),
			},
		}
		if so.RetentionPolicyEnabled {
			retentionSeconds := so.RetentionPolicyPeriodDays * 86400
			bucketArgs.RetentionPolicy = &storage.BucketRetentionPolicyArgs{
				IsLocked:        pulumi.Bool(so.RetentionPolicyIsLocked),
				RetentionPeriod: pulumi.String(fmt.Sprintf("%d", retentionSeconds)),
			}
		}

		logBucket, err := storage.NewBucket(ctx, name+"-storage", bucketArgs, childOpts...)
		if err != nil {
			return nil, err
		}
		component.StorageBucketName = logBucket.Name

		sinkName := so.LoggingSinkName
		if sinkName == "" {
			sinkName = "sk-c-logging-bkt"
		}
		destURI := logBucket.Name.ApplyT(func(n string) string {
			return fmt.Sprintf("storage.googleapis.com/%s", n)
		}).(pulumi.StringOutput)

		for resKey, resID := range args.Resources {
			sink, err := NewLogExport(ctx, fmt.Sprintf("%s-sto-%s", name, resKey), &LogExportArgs{
				DestinationURI:       destURI,
				Filter:               pulumi.String(so.LoggingSinkFilter),
				LogSinkName:          pulumi.String(sinkName),
				ParentResourceID:     pulumi.String(resID),
				ResourceType:         args.ResourceType,
				UniqueWriterIdentity: true,
				IncludeChildren:      true,
			}, childOpts...)
			if err != nil {
				return nil, err
			}

			// Grant writer identity objectCreator on the bucket
			iamMember, err := storage.NewBucketIAMMember(ctx, fmt.Sprintf("%s-sto-iam-%s", name, resKey), &storage.BucketIAMMemberArgs{
				Bucket: logBucket.Name,
				Role:   pulumi.String("roles/storage.objectCreator"),
				Member: sink.WriterIdentity,
			}, childOpts...)
			if err != nil {
				return nil, err
			}
			lastResource = iamMember
		}

		// Billing account sink → storage
		if args.EnableBillingAccountSink {
			billingSink, err := NewLogExport(ctx, name+"-sto-billing", &LogExportArgs{
				DestinationURI:       destURI,
				Filter:               pulumi.String(""),
				LogSinkName:          pulumi.Sprintf("%s-billing-%s", sinkName, suffix.Result),
				ParentResourceID:     pulumi.String(args.BillingAccount),
				ResourceType:         "billing_account",
				UniqueWriterIdentity: true,
			}, childOpts...)
			if err != nil {
				return nil, err
			}
			billingIAM, err := storage.NewBucketIAMMember(ctx, name+"-sto-iam-billing", &storage.BucketIAMMemberArgs{
				Bucket: logBucket.Name,
				Role:   pulumi.String("roles/storage.objectCreator"),
				Member: billingSink.WriterIdentity,
			}, childOpts...)
			if err != nil {
				return nil, err
			}
			lastResource = billingIAM
			billingSinkNames["storage"] = pulumi.Sprintf("%s-billing-%s", so.LoggingSinkName, suffix.Result)
		}
	}

	// ====================================================================
	// Pub/Sub destination
	// ====================================================================
	if args.PubSubOptions != nil {
		po := args.PubSubOptions

		topicName := suffix.Result.ApplyT(func(s string) string {
			if po.TopicName != "" {
				return po.TopicName
			}
			return fmt.Sprintf("tp-logs-%s", s)
		}).(pulumi.StringOutput)

		logTopic, err := pubsub.NewTopic(ctx, name+"-pubsub-topic", &pubsub.TopicArgs{
			Project: args.LoggingDestinationProjectID,
			Name:    topicName,
		}, childOpts...)
		if err != nil {
			return nil, err
		}
		component.PubSubTopicName = logTopic.Name

		if po.CreateSubscriber {
			if _, err := pubsub.NewSubscription(ctx, name+"-pubsub-sub", &pubsub.SubscriptionArgs{
				Project: args.LoggingDestinationProjectID,
				Name:    pulumi.Sprintf("sub-%s", logTopic.Name),
				Topic:   logTopic.Name,
			}, childOpts...); err != nil {
				return nil, err
			}
		}

		sinkName := po.LoggingSinkName
		if sinkName == "" {
			sinkName = "sk-c-logging-pub"
		}
		destURI := logTopic.ID().ApplyT(func(id string) string {
			return fmt.Sprintf("pubsub.googleapis.com/%s", id)
		}).(pulumi.StringOutput)

		for resKey, resID := range args.Resources {
			sink, err := NewLogExport(ctx, fmt.Sprintf("%s-pub-%s", name, resKey), &LogExportArgs{
				DestinationURI:       destURI,
				Filter:               pulumi.String(po.LoggingSinkFilter),
				LogSinkName:          pulumi.String(sinkName),
				ParentResourceID:     pulumi.String(resID),
				ResourceType:         args.ResourceType,
				UniqueWriterIdentity: true,
				IncludeChildren:      true,
			}, childOpts...)
			if err != nil {
				return nil, err
			}

			iamMember, err := pubsub.NewTopicIAMMember(ctx, fmt.Sprintf("%s-pub-iam-%s", name, resKey), &pubsub.TopicIAMMemberArgs{
				Project: args.LoggingDestinationProjectID,
				Topic:   logTopic.Name,
				Role:    pulumi.String("roles/pubsub.publisher"),
				Member:  sink.WriterIdentity,
			}, childOpts...)
			if err != nil {
				return nil, err
			}
			lastResource = iamMember
		}

		// Billing account sink → pub/sub
		if args.EnableBillingAccountSink {
			billingSink, err := NewLogExport(ctx, name+"-pub-billing", &LogExportArgs{
				DestinationURI:       destURI,
				Filter:               pulumi.String(""),
				LogSinkName:          pulumi.Sprintf("%s-billing-%s", sinkName, suffix.Result),
				ParentResourceID:     pulumi.String(args.BillingAccount),
				ResourceType:         "billing_account",
				UniqueWriterIdentity: true,
			}, childOpts...)
			if err != nil {
				return nil, err
			}
			billingIAM, err := pubsub.NewTopicIAMMember(ctx, name+"-pub-iam-billing", &pubsub.TopicIAMMemberArgs{
				Project: args.LoggingDestinationProjectID,
				Topic:   logTopic.Name,
				Role:    pulumi.String("roles/pubsub.publisher"),
				Member:  billingSink.WriterIdentity,
			}, childOpts...)
			if err != nil {
				return nil, err
			}
			lastResource = billingIAM
			billingSinkNames["pubsub"] = pulumi.Sprintf("%s-billing-%s", po.LoggingSinkName, suffix.Result)
		}
	}

	// Billing account sink → project log bucket
	if args.EnableBillingAccountSink && args.ProjectOptions != nil {
		po := args.ProjectOptions
		bucketID := po.LogBucketID
		if bucketID == "" {
			bucketID = "AggregatedLogs"
		}
		location := po.Location
		if location == "" {
			location = "global"
		}
		sinkName := po.LoggingSinkName
		if sinkName == "" {
			sinkName = "sk-c-logging-prj"
		}
		destURI := args.LoggingDestinationProjectID.ToStringOutput().ApplyT(func(projID string) string {
			return fmt.Sprintf("logging.googleapis.com/projects/%s/locations/%s/buckets/%s", projID, location, bucketID)
		}).(pulumi.StringOutput)

		billingSink, err := NewLogExport(ctx, name+"-prj-billing", &LogExportArgs{
			DestinationURI:       destURI,
			Filter:               pulumi.String(""),
			LogSinkName:          pulumi.Sprintf("%s-billing-%s", sinkName, suffix.Result),
			ParentResourceID:     pulumi.String(args.BillingAccount),
			ResourceType:         "billing_account",
			UniqueWriterIdentity: true,
		}, childOpts...)
		if err != nil {
			return nil, err
		}
		billingPrjIAM, err := projects.NewIAMMember(ctx, name+"-prj-iam-billing", &projects.IAMMemberArgs{
			Project: args.LoggingDestinationProjectID,
			Role:    pulumi.String("roles/logging.logWriter"),
			Member:  billingSink.WriterIdentity,
		}, childOpts...)
		if err != nil {
			return nil, err
		}
		lastResource = billingPrjIAM
		billingSinkNames["project"] = pulumi.Sprintf("%s-billing-%s", sinkName, suffix.Result)
	}

	component.LastResource = lastResource
	component.BillingSinkNames = billingSinkNames

	ctx.RegisterResourceOutputs(component, pulumi.Map{})
	return component, nil
}
