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

package iam

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewOrganizationIAMMember(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewOrganizationIAMMember(ctx, "test-org-iam", &OrganizationIAMMemberArgs{
			OrgID:  pulumi.String("123456"),
			Role:   pulumi.String("roles/viewer"),
			Member: pulumi.String("user:test@example.com"),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	members := tracker.RequireType(t, "gcp:organizations/iAMMember:IAMMember", 1)
	assert.Equal(t, "123456", members[0].Inputs["orgId"].StringValue())
	assert.Equal(t, "roles/viewer", members[0].Inputs["role"].StringValue())
	assert.Equal(t, "user:test@example.com", members[0].Inputs["member"].StringValue())
}

func TestNewOrganizationIAMBinding(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewOrganizationIAMBinding(ctx, "test-org-binding", &OrganizationIAMBindingArgs{
			OrgID: pulumi.String("123456"),
			Role:  pulumi.String("roles/viewer"),
			Members: pulumi.StringArray{
				pulumi.String("user:a@example.com"),
				pulumi.String("user:b@example.com"),
			},
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	bindings := tracker.RequireType(t, "gcp:organizations/iAMBinding:IAMBinding", 1)
	assert.Equal(t, "123456", bindings[0].Inputs["orgId"].StringValue())
}

func TestNewOrganizationIAMMember_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewOrganizationIAMMember(ctx, "test", nil)
		return err
	}, pulumi.WithMocks("test", "test", testutil.NewTracker()))
	require.ErrorContains(t, err, "args cannot be nil")
}

func TestNewOrganizationIAMBinding_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewOrganizationIAMBinding(ctx, "test", nil)
		return err
	}, pulumi.WithMocks("test", "test", testutil.NewTracker()))
	require.ErrorContains(t, err, "args cannot be nil")
}

func TestNewOrganizationIAMMember_EmptyName(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewOrganizationIAMMember(ctx, "", &OrganizationIAMMemberArgs{
			OrgID:  pulumi.String("123456"),
			Role:   pulumi.String("roles/viewer"),
			Member: pulumi.String("user:test@example.com"),
		})
		return err
	}, pulumi.WithMocks("test", "test", testutil.NewTracker()))
	require.Error(t, err)
}

func TestNewOrganizationIAMBinding_EmptyName(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewOrganizationIAMBinding(ctx, "", &OrganizationIAMBindingArgs{})
		return err
	}, pulumi.WithMocks("test", "test", testutil.NewTracker()))
	require.Error(t, err)
}
