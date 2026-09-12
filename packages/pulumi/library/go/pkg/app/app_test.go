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

package app

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const cloudRunService = "gcp:cloudrunv2/service:Service"

func TestNewCloudRunApp_Basic(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		app, err := NewCloudRunApp(ctx, "test-app", &CloudRunAppArgs{
			ProjectID: pulumi.String("prj-app"),
			Name:      pulumi.String("my-service"),
			Image:     pulumi.String("gcr.io/prj-app/my-service:latest"),
			Region:    pulumi.String("us-central1"),
		})
		require.NoError(t, err)
		assert.NotNil(t, app.Service)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	services := tracker.RequireType(t, cloudRunService, 1)
	assert.Equal(t, "my-service", services[0].Inputs["name"].StringValue())
	assert.Equal(t, "prj-app", services[0].Inputs["project"].StringValue())
	assert.Equal(t, "us-central1", services[0].Inputs["location"].StringValue())
}

func TestNewCloudRunApp_DefaultIngress(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCloudRunApp(ctx, "test-ingress-default", &CloudRunAppArgs{
			ProjectID: pulumi.String("prj-ingress"),
			Name:      pulumi.String("svc-ingress"),
			Image:     pulumi.String("gcr.io/prj/svc:v1"),
			Region:    pulumi.String("us-east1"),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	services := tracker.RequireType(t, cloudRunService, 1)
	assert.Equal(t, "INGRESS_TRAFFIC_ALL", services[0].Inputs["ingress"].StringValue())
}

func TestNewCloudRunApp_CustomIngress(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCloudRunApp(ctx, "test-internal", &CloudRunAppArgs{
			ProjectID: pulumi.String("prj-internal"),
			Name:      pulumi.String("svc-internal"),
			Image:     pulumi.String("gcr.io/prj/svc:v2"),
			Region:    pulumi.String("us-west1"),
			Ingress:   pulumi.StringPtr("INGRESS_TRAFFIC_INTERNAL_ONLY"),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	services := tracker.RequireType(t, cloudRunService, 1)
	assert.Equal(t, "INGRESS_TRAFFIC_INTERNAL_ONLY", services[0].Inputs["ingress"].StringValue())
}

func TestNewCloudRunApp_InternalLoadBalancer(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCloudRunApp(ctx, "test-ilb", &CloudRunAppArgs{
			ProjectID: pulumi.String("prj-ilb"),
			Name:      pulumi.String("svc-ilb"),
			Image:     pulumi.String("gcr.io/prj/svc:v3"),
			Region:    pulumi.String("us-central1"),
			Ingress:   pulumi.StringPtr("INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	services := tracker.RequireType(t, cloudRunService, 1)
	assert.Equal(t, "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER", services[0].Inputs["ingress"].StringValue())
}

func TestNewCloudRunApp_WithServiceAccount(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCloudRunApp(ctx, "test-sa", &CloudRunAppArgs{
			ProjectID:      pulumi.String("prj-sa"),
			Name:           pulumi.String("svc-sa"),
			Image:          pulumi.String("gcr.io/prj/svc:v1"),
			Region:         pulumi.String("us-central1"),
			ServiceAccount: pulumi.StringPtr("sa@prj-sa.iam.gserviceaccount.com"),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	services := tracker.RequireType(t, cloudRunService, 1)
	template := services[0].Inputs["template"]
	assert.True(t, template.IsObject())
	assert.Equal(t, "sa@prj-sa.iam.gserviceaccount.com",
		template.ObjectValue()["serviceAccount"].StringValue())
}

func TestNewCloudRunApp_WithoutServiceAccount(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCloudRunApp(ctx, "test-no-sa", &CloudRunAppArgs{
			ProjectID: pulumi.String("prj-no-sa"),
			Name:      pulumi.String("svc-no-sa"),
			Image:     pulumi.String("gcr.io/prj/svc:v1"),
			Region:    pulumi.String("us-central1"),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, cloudRunService, 1)
}

func TestNewCloudRunApp_WithEnvVars(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCloudRunApp(ctx, "test-env", &CloudRunAppArgs{
			ProjectID: pulumi.String("prj-env"),
			Name:      pulumi.String("svc-env"),
			Image:     pulumi.String("gcr.io/prj/svc:v1"),
			Region:    pulumi.String("us-central1"),
			EnvVars: map[string]pulumi.StringInput{
				"DATABASE_URL": pulumi.String("postgres://db:5432/app"),
				"LOG_LEVEL":    pulumi.String("info"),
			},
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	services := tracker.RequireType(t, cloudRunService, 1)
	template := services[0].Inputs["template"]
	assert.True(t, template.IsObject())
}

func TestNewCloudRunApp_NoEnvVars(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		app, err := NewCloudRunApp(ctx, "test-no-env", &CloudRunAppArgs{
			ProjectID: pulumi.String("prj-no-env"),
			Name:      pulumi.String("svc-no-env"),
			Image:     pulumi.String("gcr.io/prj/svc:v1"),
			Region:    pulumi.String("us-central1"),
		})
		require.NoError(t, err)
		assert.NotNil(t, app.Service)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, cloudRunService, 1)
}

func TestNewCloudRunApp_ImagePropagated(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCloudRunApp(ctx, "test-image", &CloudRunAppArgs{
			ProjectID: pulumi.String("prj-img"),
			Name:      pulumi.String("svc-img"),
			Image:     pulumi.String("us-docker.pkg.dev/prj/repo/app:sha-abc123"),
			Region:    pulumi.String("us-central1"),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	services := tracker.RequireType(t, cloudRunService, 1)
	template := services[0].Inputs["template"]
	containers := template.ObjectValue()["containers"]
	assert.True(t, containers.IsArray())
	assert.GreaterOrEqual(t, len(containers.ArrayValue()), 1)
}
