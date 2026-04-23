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
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	orgSinkType     = "gcp:logging/organizationSink:OrganizationSink"
	folderSinkType  = "gcp:logging/folderSink:FolderSink"
	projectSinkType = "gcp:logging/projectSink:ProjectSink"
	billingSinkType = "gcp:logging/billingAccountSink:BillingAccountSink"
)

// ---------- LogExport: Organization Sink ----------

func TestLogExport_OrganizationSink(t *testing.T) {
	tracker := testutil.NewTracker()
	tracker.OutputOverrides[orgSinkType] = testutil.PropMap(map[string]interface{}{
		"writerIdentity": "serviceAccount:o123-456@gcp-sa-logging.iam.gserviceaccount.com",
	})

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		le, err := NewLogExport(ctx, "test-org-sink", &LogExportArgs{
			DestinationURI:   pulumi.String("storage.googleapis.com/my-bucket"),
			Filter:           pulumi.String("logName: /logs/cloudaudit"),
			LogSinkName:      pulumi.String("sk-test"),
			ParentResourceID: pulumi.String("123456789"),
			ResourceType:     "organization",
			IncludeChildren:  true,
		})
		require.NoError(t, err)
		assert.NotNil(t, le)
		assert.NotNil(t, le.Sink)
		return nil
	}, pulumi.WithMocks("test", "test", tracker))
	require.NoError(t, err)

	sinks := tracker.RequireType(t, orgSinkType, 1)
	assert.Equal(t, "sk-test", sinks[0].Inputs["name"].StringValue())
	assert.Equal(t, "123456789", sinks[0].Inputs["orgId"].StringValue())
	assert.Equal(t, "storage.googleapis.com/my-bucket", sinks[0].Inputs["destination"].StringValue())
	assert.True(t, sinks[0].Inputs["includeChildren"].BoolValue())
}

// ---------- LogExport: Folder Sink ----------

func TestLogExport_FolderSink(t *testing.T) {
	tracker := testutil.NewTracker()
	tracker.OutputOverrides[folderSinkType] = testutil.PropMap(map[string]interface{}{
		"writerIdentity": "serviceAccount:f789@gcp-sa-logging.iam.gserviceaccount.com",
	})

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		le, err := NewLogExport(ctx, "test-folder-sink", &LogExportArgs{
			DestinationURI:   pulumi.String("pubsub.googleapis.com/projects/p/topics/t"),
			Filter:           pulumi.String(""),
			LogSinkName:      pulumi.String("sk-folder"),
			ParentResourceID: pulumi.String("folders/456"),
			ResourceType:     "folder",
			IncludeChildren:  true,
		})
		require.NoError(t, err)
		assert.NotNil(t, le)
		return nil
	}, pulumi.WithMocks("test", "test", tracker))
	require.NoError(t, err)

	sinks := tracker.RequireType(t, folderSinkType, 1)
	assert.Equal(t, "sk-folder", sinks[0].Inputs["name"].StringValue())
	assert.Equal(t, "folders/456", sinks[0].Inputs["folder"].StringValue())
}

// ---------- LogExport: Project Sink ----------

func TestLogExport_ProjectSink(t *testing.T) {
	tracker := testutil.NewTracker()
	tracker.OutputOverrides[projectSinkType] = testutil.PropMap(map[string]interface{}{
		"writerIdentity": "serviceAccount:p123@gcp-sa-logging.iam.gserviceaccount.com",
	})

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		le, err := NewLogExport(ctx, "test-project-sink", &LogExportArgs{
			DestinationURI:       pulumi.String("logging.googleapis.com/projects/p/locations/us/buckets/b"),
			Filter:               pulumi.String(""),
			LogSinkName:          pulumi.String("sk-project"),
			ParentResourceID:     pulumi.String("my-project"),
			ResourceType:         "project",
			UniqueWriterIdentity: true,
		})
		require.NoError(t, err)
		assert.NotNil(t, le)
		return nil
	}, pulumi.WithMocks("test", "test", tracker))
	require.NoError(t, err)

	sinks := tracker.RequireType(t, projectSinkType, 1)
	assert.Equal(t, "sk-project", sinks[0].Inputs["name"].StringValue())
	assert.Equal(t, "my-project", sinks[0].Inputs["project"].StringValue())
	assert.True(t, sinks[0].Inputs["uniqueWriterIdentity"].BoolValue())
}

// ---------- LogExport: Billing Account Sink ----------

func TestLogExport_BillingAccountSink(t *testing.T) {
	tracker := testutil.NewTracker()
	tracker.OutputOverrides[billingSinkType] = testutil.PropMap(map[string]interface{}{
		"writerIdentity": "serviceAccount:billing@gcp-sa-logging.iam.gserviceaccount.com",
	})

	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		le, err := NewLogExport(ctx, "test-billing-sink", &LogExportArgs{
			DestinationURI:   pulumi.String("storage.googleapis.com/billing-bucket"),
			Filter:           pulumi.String(""),
			LogSinkName:      pulumi.String("sk-billing"),
			ParentResourceID: pulumi.String("AAAAAA-BBBBBB-CCCCCC"),
			ResourceType:     "billing_account",
		})
		require.NoError(t, err)
		assert.NotNil(t, le)
		return nil
	}, pulumi.WithMocks("test", "test", tracker))
	require.NoError(t, err)

	sinks := tracker.RequireType(t, billingSinkType, 1)
	assert.Equal(t, "sk-billing", sinks[0].Inputs["name"].StringValue())
	assert.Equal(t, "AAAAAA-BBBBBB-CCCCCC", sinks[0].Inputs["billingAccount"].StringValue())
}

// ---------- LogExport: Invalid Resource Type ----------

func TestLogExport_InvalidResourceType(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewLogExport(ctx, "test-invalid", &LogExportArgs{
			DestinationURI:   pulumi.String("storage.googleapis.com/bucket"),
			Filter:           pulumi.String(""),
			LogSinkName:      pulumi.String("sk-bad"),
			ParentResourceID: pulumi.String("123"),
			ResourceType:     "invalid",
		})
		return err
	}, pulumi.WithMocks("test", "test", tracker))
	require.Error(t, err)
	assert.Contains(t, err.Error(), "unsupported resource_type")
}

// ---------- LogExport: Nil Args ----------

func TestLogExport_NilArgs(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewLogExport(ctx, "test-nil", nil)
		return err
	}, pulumi.WithMocks("test", "test", tracker))
	require.Error(t, err)
	assert.Contains(t, err.Error(), "args cannot be nil")
}
