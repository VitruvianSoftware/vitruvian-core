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
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	storageBucketType   = "gcp:storage/bucket:Bucket"
	bucketIAMType       = "gcp:storage/bucketIAMMember:BucketIAMMember"
	pubsubTopicType     = "gcp:pubsub/topic:Topic"
	pubsubSubType       = "gcp:pubsub/subscription:Subscription"
	topicIAMType        = "gcp:pubsub/topicIAMMember:TopicIAMMember"
	projectIAMType      = "gcp:projects/iAMMember:IAMMember"
	logBucketConfigType = "gcp:logging/projectBucketConfig:ProjectBucketConfig"
	linkedDatasetType   = "gcp:logging/linkedDataset:LinkedDataset"
	randomStringType    = "random:index/randomString:RandomString"
)

func sinkOverrides() map[string]resource.PropertyMap {
	writerID := map[string]interface{}{
		"writerIdentity": "serviceAccount:mock@gcp-sa-logging.iam.gserviceaccount.com",
	}
	return map[string]resource.PropertyMap{
		orgSinkType:     testutil.PropMap(writerID),
		folderSinkType:  testutil.PropMap(writerID),
		projectSinkType: testutil.PropMap(writerID),
		billingSinkType: testutil.PropMap(writerID),
	}
}

// ---------- CentralizedLogging: Nil Args ----------

func TestCentralizedLogging_NilArgs(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCentralizedLogging(ctx, "test", nil)
		return err
	}, pulumi.WithMocks("test", "test", tracker))
	require.Error(t, err)
	assert.Contains(t, err.Error(), "args cannot be nil")
}

// ---------- CentralizedLogging: Empty Resources ----------

func TestCentralizedLogging_EmptyResources(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCentralizedLogging(ctx, "test", &CentralizedLoggingArgs{
			Resources:                   map[string]string{},
			ResourceType:                "organization",
			LoggingDestinationProjectID: pulumi.String("audit-project"),
		})
		return err
	}, pulumi.WithMocks("test", "test", tracker))
	require.Error(t, err)
	assert.Contains(t, err.Error(), "resources map must have at least 1 item")
}

// ---------- CentralizedLogging: Organization with All Destinations ----------

func TestCentralizedLogging_OrgAllDestinations(t *testing.T) {
	tracker := testutil.NewTracker()
	for k, v := range sinkOverrides() {
		tracker.OutputOverrides[k] = v
	}
	tracker.OutputOverrides[randomStringType] = testutil.PropMap(map[string]interface{}{
		"result": "ab12",
	})
	tracker.OutputOverrides[pubsubTopicType] = testutil.PropMap(map[string]interface{}{
		"name": "tp-org-logs-ab12",
	})
	tracker.OutputOverrides[storageBucketType] = testutil.PropMap(map[string]interface{}{
		"name": "bkt-audit-project-org-logs-ab12",
	})

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cl, err := NewCentralizedLogging(ctx, "logs", &CentralizedLoggingArgs{
			Resources:                   map[string]string{"resource": "123456"},
			ResourceType:                "organization",
			LoggingDestinationProjectID: pulumi.String("audit-project"),
			BillingAccount:              "AAAAAA-BBBBBB-CCCCCC",
			EnableBillingAccountSink:    true,
			StorageOptions: &StorageOptions{
				LoggingSinkName:   "sk-c-logging-bkt",
				LoggingSinkFilter: "logName: /logs/cloudaudit",
				Location:          "US",
				Versioning:        true,
			},
			PubSubOptions: &PubSubOptions{
				LoggingSinkName:   "sk-c-logging-pub",
				LoggingSinkFilter: "logName: /logs/cloudaudit",
				TopicName:         "tp-org-logs",
				CreateSubscriber:  true,
			},
			ProjectOptions: &ProjectOptions{
				LoggingSinkName:          "sk-c-logging-prj",
				LoggingSinkFilter:        "logName: /logs/cloudaudit",
				LogBucketID:              "AggregatedLogs",
				LogBucketDescription:     "Aggregated logs bucket",
				Location:                 "us-central1",
				EnableAnalytics:          true,
				LinkedDatasetID:          "ds_aggregated_logs",
				LinkedDatasetDescription: "Linked dataset for analytics",
			},
		})
		require.NoError(t, err)
		assert.NotNil(t, cl)
		assert.NotNil(t, cl.LastResource)
		return nil
	}, pulumi.WithMocks("test", "test", tracker))
	require.NoError(t, err)

	// Verify destinations created
	tracker.RequireType(t, storageBucketType, 1)
	tracker.RequireType(t, pubsubTopicType, 1)
	tracker.RequireType(t, logBucketConfigType, 1)
	tracker.RequireType(t, linkedDatasetType, 1)
	tracker.RequireType(t, pubsubSubType, 1) // subscriber

	// 1 resource org sink per destination (3) + 3 billing sinks + 1 internal project sink = 7
	// But sinks are wrapped in LogExport components, so count underlying sinks
	orgSinks := tracker.TypeCount(orgSinkType)
	assert.Equal(t, 3, orgSinks, "should have 3 org sinks (sto, pub, prj)")

	billingSinks := tracker.TypeCount(billingSinkType)
	assert.Equal(t, 3, billingSinks, "should have 3 billing sinks")

	projectSinks := tracker.TypeCount(projectSinkType)
	assert.Equal(t, 1, projectSinks, "should have 1 internal project sink")

	// Verify IAM grants
	storageIAM := tracker.TypeCount(bucketIAMType)
	assert.GreaterOrEqual(t, storageIAM, 1, "should have storage IAM grants")

	pubsubIAM := tracker.TypeCount(topicIAMType)
	assert.GreaterOrEqual(t, pubsubIAM, 1, "should have pubsub IAM grants")

	projectIAM := tracker.TypeCount(projectIAMType)
	assert.GreaterOrEqual(t, projectIAM, 1, "should have project IAM grants")
}

// ---------- CentralizedLogging: Folder Sinks ----------

func TestCentralizedLogging_FolderSinks(t *testing.T) {
	tracker := testutil.NewTracker()
	for k, v := range sinkOverrides() {
		tracker.OutputOverrides[k] = v
	}
	tracker.OutputOverrides[randomStringType] = testutil.PropMap(map[string]interface{}{
		"result": "cd34",
	})
	tracker.OutputOverrides[storageBucketType] = testutil.PropMap(map[string]interface{}{
		"name": "bkt-logs",
	})

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cl, err := NewCentralizedLogging(ctx, "folder-logs", &CentralizedLoggingArgs{
			Resources:                   map[string]string{"resource": "folders/789"},
			ResourceType:                "folder",
			LoggingDestinationProjectID: pulumi.String("audit-folder-proj"),
			StorageOptions: &StorageOptions{
				LoggingSinkFilter: "",
				Location:          "us-central1",
			},
		})
		require.NoError(t, err)
		assert.NotNil(t, cl)
		return nil
	}, pulumi.WithMocks("test", "test", tracker))
	require.NoError(t, err)

	// Should use FolderSink, not OrganizationSink
	folderSinks := tracker.TypeCount(folderSinkType)
	assert.Equal(t, 1, folderSinks, "should create folder sinks when ResourceType=folder")

	orgSinks := tracker.TypeCount(orgSinkType)
	assert.Equal(t, 0, orgSinks, "should NOT create org sinks when ResourceType=folder")
}

// ---------- CentralizedLogging: Storage Only ----------

func TestCentralizedLogging_StorageOnly(t *testing.T) {
	tracker := testutil.NewTracker()
	for k, v := range sinkOverrides() {
		tracker.OutputOverrides[k] = v
	}
	tracker.OutputOverrides[randomStringType] = testutil.PropMap(map[string]interface{}{
		"result": "ef56",
	})
	tracker.OutputOverrides[storageBucketType] = testutil.PropMap(map[string]interface{}{
		"name": "bkt-logs-ef56",
	})

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cl, err := NewCentralizedLogging(ctx, "sto-only", &CentralizedLoggingArgs{
			Resources:                   map[string]string{"resource": "111222"},
			ResourceType:                "organization",
			LoggingDestinationProjectID: pulumi.String("audit-proj"),
			StorageOptions: &StorageOptions{
				LoggingSinkFilter: "",
				Location:          "US",
			},
		})
		require.NoError(t, err)
		assert.NotNil(t, cl)
		return nil
	}, pulumi.WithMocks("test", "test", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, storageBucketType, 1)
	assert.Equal(t, 0, tracker.TypeCount(pubsubTopicType), "no pubsub when PubSubOptions is nil")
	assert.Equal(t, 0, tracker.TypeCount(logBucketConfigType), "no log bucket when ProjectOptions is nil")
}

// ---------- CentralizedLogging: No Billing Sinks ----------

func TestCentralizedLogging_NoBillingSinks(t *testing.T) {
	tracker := testutil.NewTracker()
	for k, v := range sinkOverrides() {
		tracker.OutputOverrides[k] = v
	}
	tracker.OutputOverrides[randomStringType] = testutil.PropMap(map[string]interface{}{
		"result": "gh78",
	})
	tracker.OutputOverrides[storageBucketType] = testutil.PropMap(map[string]interface{}{
		"name": "bkt",
	})

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCentralizedLogging(ctx, "no-billing", &CentralizedLoggingArgs{
			Resources:                   map[string]string{"resource": "999"},
			ResourceType:                "organization",
			LoggingDestinationProjectID: pulumi.String("audit"),
			EnableBillingAccountSink:    false,
			StorageOptions: &StorageOptions{
				LoggingSinkFilter: "",
				Location:          "US",
			},
		})
		return err
	}, pulumi.WithMocks("test", "test", tracker))
	require.NoError(t, err)

	assert.Equal(t, 0, tracker.TypeCount(billingSinkType),
		"no billing sinks when EnableBillingAccountSink=false")
}

// ---------- CentralizedLogging: Storage Retention Policy ----------

func TestCentralizedLogging_StorageRetentionPolicy(t *testing.T) {
	tracker := testutil.NewTracker()
	for k, v := range sinkOverrides() {
		tracker.OutputOverrides[k] = v
	}
	tracker.OutputOverrides[randomStringType] = testutil.PropMap(map[string]interface{}{
		"result": "ij90",
	})
	tracker.OutputOverrides[storageBucketType] = testutil.PropMap(map[string]interface{}{
		"name": "bkt-retention",
	})

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCentralizedLogging(ctx, "retention", &CentralizedLoggingArgs{
			Resources:                   map[string]string{"resource": "888"},
			ResourceType:                "organization",
			LoggingDestinationProjectID: pulumi.String("audit"),
			StorageOptions: &StorageOptions{
				LoggingSinkFilter:         "",
				Location:                  "US",
				RetentionPolicyEnabled:    true,
				RetentionPolicyIsLocked:   true,
				RetentionPolicyPeriodDays: 365,
			},
		})
		return err
	}, pulumi.WithMocks("test", "test", tracker))
	require.NoError(t, err)

	buckets := tracker.RequireType(t, storageBucketType, 1)
	rp := buckets[0].Inputs["retentionPolicy"]
	require.True(t, rp.IsObject(), "retentionPolicy should be set")
	assert.True(t, rp.ObjectValue()["isLocked"].BoolValue())
	// 365 days * 86400 seconds = 31536000
	assert.Equal(t, "31536000", rp.ObjectValue()["retentionPeriod"].StringValue())
}

// ---------- CentralizedLogging: PubSub No Subscriber ----------

func TestCentralizedLogging_PubSubNoSubscriber(t *testing.T) {
	tracker := testutil.NewTracker()
	for k, v := range sinkOverrides() {
		tracker.OutputOverrides[k] = v
	}
	tracker.OutputOverrides[randomStringType] = testutil.PropMap(map[string]interface{}{
		"result": "kl12",
	})
	tracker.OutputOverrides[pubsubTopicType] = testutil.PropMap(map[string]interface{}{
		"name": "tp-no-sub",
	})

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCentralizedLogging(ctx, "no-sub", &CentralizedLoggingArgs{
			Resources:                   map[string]string{"resource": "777"},
			ResourceType:                "organization",
			LoggingDestinationProjectID: pulumi.String("audit"),
			PubSubOptions: &PubSubOptions{
				LoggingSinkFilter: "",
				CreateSubscriber:  false,
			},
		})
		return err
	}, pulumi.WithMocks("test", "test", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, pubsubTopicType, 1)
	assert.Equal(t, 0, tracker.TypeCount(pubsubSubType),
		"no subscription when CreateSubscriber=false")
}

// ---------- CentralizedLogging: Internal Project Sink ----------

func TestCentralizedLogging_InternalProjectSink(t *testing.T) {
	tracker := testutil.NewTracker()
	for k, v := range sinkOverrides() {
		tracker.OutputOverrides[k] = v
	}
	tracker.OutputOverrides[randomStringType] = testutil.PropMap(map[string]interface{}{
		"result": "mn34",
	})

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCentralizedLogging(ctx, "internal", &CentralizedLoggingArgs{
			Resources:                   map[string]string{"resource": "666"},
			ResourceType:                "organization",
			LoggingDestinationProjectID: pulumi.String("audit"),
			ProjectOptions: &ProjectOptions{
				LoggingSinkFilter: "",
				LogBucketID:       "AggregatedLogs",
				Location:          "us-central1",
				EnableAnalytics:   true,
				LinkedDatasetID:   "ds_test",
			},
		})
		return err
	}, pulumi.WithMocks("test", "test", tracker))
	require.NoError(t, err)

	// Should create both an org sink AND an internal project sink
	orgSinks := tracker.TypeCount(orgSinkType)
	assert.Equal(t, 1, orgSinks, "1 org sink for the project destination")

	projectSinks := tracker.TypeCount(projectSinkType)
	assert.Equal(t, 1, projectSinks, "1 internal project sink for blind-spot coverage")

	// The internal sink name should end with "-la"
	for _, r := range tracker.ByType(projectSinkType) {
		sinkName := r.Inputs["name"].StringValue()
		assert.Contains(t, sinkName, "-la", "internal sink name should end with -la")
	}
}
