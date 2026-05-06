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

package compute_instance

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/require"
)

func TestNewComputeInstance_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewComputeInstance(ctx, "test", nil)
		require.Error(t, err)
		require.Contains(t, err.Error(), "args is required")
		return nil
	}, pulumi.WithMocks("project", "stack", testutil.NewTracker()))
	require.NoError(t, err)
}

func TestNewComputeInstance_Single(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		result, err := NewComputeInstance(ctx, "test-inst", &ComputeInstanceArgs{
			Project:          pulumi.String("test-proj"),
			Zone:             "us-central1-a",
			Hostname:         "my-instance",
			InstanceTemplate: pulumi.String("projects/test/global/instanceTemplates/tmpl"),
		})
		require.NoError(t, err)
		require.Len(t, result.Instances, 1)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:compute/instanceFromTemplate:InstanceFromTemplate", 1)
}

func TestNewComputeInstance_Multiple(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		result, err := NewComputeInstance(ctx, "test-multi", &ComputeInstanceArgs{
			Project:          pulumi.String("test-proj"),
			Zone:             "us-central1-a",
			Hostname:         "web-server",
			InstanceTemplate: pulumi.String("projects/test/global/instanceTemplates/tmpl"),
			NumInstances:     3,
		})
		require.NoError(t, err)
		require.Len(t, result.Instances, 3)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:compute/instanceFromTemplate:InstanceFromTemplate", 3)
}

func TestNewComputeInstance_DeletionProtection(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewComputeInstance(ctx, "test-protected", &ComputeInstanceArgs{
			Project:            pulumi.String("test-proj"),
			Zone:               "us-central1-a",
			Hostname:           "protected-instance",
			InstanceTemplate:   pulumi.String("projects/test/global/instanceTemplates/tmpl"),
			DeletionProtection: true,
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:compute/instanceFromTemplate:InstanceFromTemplate", 1)
}
