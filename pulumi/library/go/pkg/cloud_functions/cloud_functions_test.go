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

package cloud_functions

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/require"
)

func TestNewCloudFunction_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCloudFunction(ctx, "test", nil)
		require.Error(t, err)
		require.Contains(t, err.Error(), "args is required")
		return nil
	}, pulumi.WithMocks("project", "stack", testutil.NewTracker()))
	require.NoError(t, err)
}

func TestNewCloudFunction_Basic(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCloudFunction(ctx, "test-fn", &CloudFunctionArgs{
			ProjectID:    pulumi.String("test-proj"),
			Region:       "us-central1",
			Name:         "my-function",
			EntryPoint:   "main",
			SourceBucket: pulumi.String("source-bucket"),
			SourceObject: pulumi.String("function.zip"),
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:cloudfunctionsv2/function:Function", 1)
}

func TestNewCloudFunction_WithEventTrigger(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCloudFunction(ctx, "test-event", &CloudFunctionArgs{
			ProjectID:           pulumi.String("test-proj"),
			Region:              "us-central1",
			Name:                "event-function",
			Runtime:             "python310",
			EntryPoint:          "handler",
			SourceBucket:        pulumi.String("source-bucket"),
			SourceObject:        pulumi.String("function.zip"),
			EventTriggerType:    "google.cloud.pubsub.topic.v1.messagePublished",
			ServiceAccountEmail: pulumi.String("sa@test.iam.gserviceaccount.com"),
			AvailableMemory:     "512M",
			Timeout:             120,
			Labels:              map[string]string{"env": "prod"},
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:cloudfunctionsv2/function:Function", 1)
}
