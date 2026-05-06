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

package instance_template

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/require"
)

func TestNewInstanceTemplate_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewInstanceTemplate(ctx, "test", nil)
		require.Error(t, err)
		require.Contains(t, err.Error(), "args is required")
		return nil
	}, pulumi.WithMocks("project", "stack", testutil.NewTracker()))
	require.NoError(t, err)
}

func TestNewInstanceTemplate_Basic(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewInstanceTemplate(ctx, "test-tmpl", &InstanceTemplateArgs{
			Project:     pulumi.String("test-proj"),
			Region:      "us-central1",
			SourceImage: "projects/debian-cloud/global/images/family/debian-11",
			Network:     pulumi.String("projects/test/global/networks/vpc"),
			Subnetwork:  pulumi.String("projects/test/regions/us-central1/subnetworks/subnet"),
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:compute/instanceTemplate:InstanceTemplate", 1)
}

func TestNewInstanceTemplate_WithShieldedVm(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewInstanceTemplate(ctx, "test-shielded", &InstanceTemplateArgs{
			Project:             pulumi.String("test-proj"),
			Region:              "us-central1",
			MachineType:         "n2-standard-4",
			SourceImage:         "projects/cos-cloud/global/images/family/cos-stable",
			DiskSizeGb:          50,
			DiskType:            "pd-ssd",
			Network:             pulumi.String("projects/test/global/networks/vpc"),
			Subnetwork:          pulumi.String("projects/test/regions/us-central1/subnetworks/subnet"),
			ServiceAccountEmail: pulumi.String("sa@test.iam.gserviceaccount.com"),
			Tags:                []string{"allow-ssh"},
			Labels:              map[string]string{"env": "prod"},
			Metadata:            map[string]string{"startup-script": "#!/bin/bash\necho hello"},
			EnableShieldedVm:    true,
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:compute/instanceTemplate:InstanceTemplate", 1)
}

func TestNewInstanceTemplate_ConfidentialVm(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewInstanceTemplate(ctx, "test-confidential", &InstanceTemplateArgs{
			Project:              pulumi.String("test-proj"),
			Region:               "us-central1",
			MachineType:          "n2d-standard-2",
			SourceImage:          "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts",
			Network:              pulumi.String("projects/test/global/networks/vpc"),
			Subnetwork:           pulumi.String("projects/test/regions/us-central1/subnetworks/subnet"),
			EnableConfidentialVm: true,
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:compute/instanceTemplate:InstanceTemplate", 1)
}
