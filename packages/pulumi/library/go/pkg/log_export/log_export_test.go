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

package log_export

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/require"
)

func TestNewLogExport_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewLogExport(ctx, "test", nil)
		require.Error(t, err)
		require.Contains(t, err.Error(), "args is required")
		return nil
	}, pulumi.WithMocks("project", "stack", testutil.NewTracker()))
	require.NoError(t, err)
}

func TestNewLogExport_Organization(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewLogExport(ctx, "test-org", &LogExportArgs{
			DestinationURI:   pulumi.String("storage.googleapis.com/my-bucket"),
			Filter:           pulumi.String("severity >= ERROR"),
			LogSinkName:      pulumi.String("org-sink"),
			ParentResourceID: pulumi.String("123456789"),
			ResourceType:     "organization",
			IncludeChildren:  true,
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:logging/organizationSink:OrganizationSink", 1)
}

func TestNewLogExport_Folder(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewLogExport(ctx, "test-folder", &LogExportArgs{
			DestinationURI:   pulumi.String("pubsub.googleapis.com/projects/p/topics/t"),
			Filter:           pulumi.String(""),
			LogSinkName:      pulumi.String("folder-sink"),
			ParentResourceID: pulumi.String("folders/987654321"),
			ResourceType:     "folder",
			IncludeChildren:  true,
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:logging/folderSink:FolderSink", 1)
}

func TestNewLogExport_Project(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewLogExport(ctx, "test-project", &LogExportArgs{
			DestinationURI:       pulumi.String("logging.googleapis.com/projects/p/locations/l/buckets/b"),
			Filter:               pulumi.String("resource.type = gce_instance"),
			LogSinkName:          pulumi.String("project-sink"),
			ParentResourceID:     pulumi.String("test-project-id"),
			ResourceType:         "project",
			UniqueWriterIdentity: true,
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:logging/projectSink:ProjectSink", 1)
}

func TestNewLogExport_BillingAccount(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewLogExport(ctx, "test-billing", &LogExportArgs{
			DestinationURI:   pulumi.String("storage.googleapis.com/billing-logs"),
			Filter:           pulumi.String(""),
			LogSinkName:      pulumi.String("billing-sink"),
			ParentResourceID: pulumi.String("AABBCC-112233-DDEEFF"),
			ResourceType:     "billing_account",
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:logging/billingAccountSink:BillingAccountSink", 1)
}

func TestNewLogExport_InvalidType(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewLogExport(ctx, "test-invalid", &LogExportArgs{
			DestinationURI:   pulumi.String("storage.googleapis.com/bucket"),
			LogSinkName:      pulumi.String("sink"),
			ParentResourceID: pulumi.String("123"),
			ResourceType:     "invalid",
		})
		require.Error(t, err)
		require.Contains(t, err.Error(), "unsupported resource_type")
		return nil
	}, pulumi.WithMocks("project", "stack", testutil.NewTracker()))
	require.NoError(t, err)
}
