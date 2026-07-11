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

package cloud_run

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/require"
)

func TestNewCloudRun_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCloudRun(ctx, "test", nil)
		require.Error(t, err)
		require.Contains(t, err.Error(), "args is required")
		return nil
	}, pulumi.WithMocks("project", "stack", testutil.NewTracker()))
	require.NoError(t, err)
}

func TestNewCloudRun_Basic(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		cr, err := NewCloudRun(ctx, "app", &CloudRunArgs{
			ProjectID:           pulumi.String("prj-d-bu1-oss-floating-2ad6"),
			Region:              "us-west1",
			Name:                "oauth-user-inspector",
			Image:               pulumi.String("us-west1-docker.pkg.dev/p/r/app@sha256:abc"),
			ServiceAccountEmail: pulumi.String("rt@prj.iam.gserviceaccount.com"),
		})
		require.NoError(t, err)
		require.NotNil(t, cr.Service)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:cloudrunv2/service:Service", 1)
}

func TestNewCloudRun_WithSecretEnv(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCloudRun(ctx, "app", &CloudRunArgs{
			ProjectID:           pulumi.String("test-proj"),
			Region:              "us-west1",
			Name:                "app",
			Image:               pulumi.String("img@sha256:abc"),
			ServiceAccountEmail: pulumi.String("rt@test.iam.gserviceaccount.com"),
			Env:                 map[string]string{"SECRET_PREFIX": "OAUTH_USER_INSPECTOR_"},
			SecretEnv: []SecretEnv{
				{Name: "GITHUB_APP_OAUTH_CLIENT_ID", SecretName: pulumi.String("oui-github-oauth-client-id"), Version: "latest"},
			},
			MinInstances: 0,
			MaxInstances: 3,
			Labels:       map[string]string{"app": "oauth-user-inspector"},
		})
		require.NoError(t, err)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:cloudrunv2/service:Service", 1)
}

func TestNewCloudRun_RequiresRegionAndName(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewCloudRun(ctx, "test", &CloudRunArgs{Name: "x"})
		require.Error(t, err)
		require.Contains(t, err.Error(), "Region is required")
		return nil
	}, pulumi.WithMocks("project", "stack", testutil.NewTracker()))
	require.NoError(t, err)
}
