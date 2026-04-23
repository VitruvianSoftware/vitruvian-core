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

package vpc_sc

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/accesscontextmanager"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/require"
)

func TestNewVpcServiceControls(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewVpcServiceControls(ctx, "test-vpcsc", &VpcServiceControlsArgs{
			PolicyID:           pulumi.String("accessPolicies/12345"),
			Prefix:             "test",
			Members:            []string{"user:test@example.com"},
			MembersDryRun:      []string{"user:dryrun@example.com"},
			ProjectNumbers:     []string{"123456789"},
			RestrictedServices: []string{"storage.googleapis.com"},
			Enforce:            true,
			IngressPolicies: accesscontextmanager.ServicePerimeterStatusIngressPolicyArray{
				&accesscontextmanager.ServicePerimeterStatusIngressPolicyArgs{},
			},
		})
		require.NoError(t, err)

		// Test non-enforce
		_, err = NewVpcServiceControls(ctx, "test-vpcsc-dry", &VpcServiceControlsArgs{
			PolicyID:           pulumi.String("accessPolicies/12345"),
			Prefix:             "test-dry",
			Members:            []string{"user:test@example.com"},
			ProjectNumbers:     []string{"123456789"},
			RestrictedServices: []string{"storage.googleapis.com"},
			Enforce:            false,
		})
		require.NoError(t, err)

		// Test empty members and services
		_, err = NewVpcServiceControls(ctx, "test-vpcsc-empty", &VpcServiceControlsArgs{
			PolicyID:       pulumi.String("accessPolicies/12345"),
			Prefix:         "test-empty",
			ProjectNumbers: []string{"123456789"},
			Enforce:        true,
		})
		require.NoError(t, err)

		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	err = pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewVpcServiceControls(ctx, "test-nil", nil)
		require.Error(t, err)
		require.Equal(t, "args is required", err.Error())
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", testutil.NewTracker()))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:accesscontextmanager/accessLevel:AccessLevel", 6)
	tracker.RequireType(t, "gcp:accesscontextmanager/servicePerimeter:ServicePerimeter", 3)
}

func TestGetDefaultRestrictedServices(t *testing.T) {
	services := GetDefaultRestrictedServices()
	require.NotEmpty(t, services)
	require.Contains(t, services, "compute.googleapis.com")
}
