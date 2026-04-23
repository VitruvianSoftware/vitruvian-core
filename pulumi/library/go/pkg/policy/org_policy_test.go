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

package policy

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const orgPolicyType = "gcp:orgpolicy/policy:Policy"

func TestNewOrgPolicy_BooleanEnforce(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		p, err := NewOrgPolicy(ctx, "test-bool-enforce", &OrgPolicyArgs{
			ParentID:   pulumi.String("organizations/123456"),
			Constraint: pulumi.String("constraints/compute.disableSerialPortAccess"),
			Boolean:    pulumi.Bool(true),
		})
		require.NoError(t, err)
		assert.NotNil(t, p.Policy)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	policies := tracker.RequireType(t, orgPolicyType, 1)
	assert.Equal(t, "organizations/123456", policies[0].Inputs["parent"].StringValue())
}

func TestNewOrgPolicy_BooleanFalse(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewOrgPolicy(ctx, "test-bool-false", &OrgPolicyArgs{
			ParentID:   pulumi.String("organizations/789"),
			Constraint: pulumi.String("constraints/compute.disableVpcExternalIpv6"),
			Boolean:    pulumi.Bool(false),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	policies := tracker.RequireType(t, orgPolicyType, 1)
	spec := policies[0].Inputs["spec"]
	assert.True(t, spec.IsObject(), "spec should be present for boolean constraint")
}

func TestNewOrgPolicy_DenyAll(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewOrgPolicy(ctx, "test-deny-all", &OrgPolicyArgs{
			ParentID:   pulumi.String("folders/111"),
			Constraint: pulumi.String("constraints/iam.allowedPolicyMemberDomains"),
			DenyAll:    pulumi.Bool(true),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, orgPolicyType, 1)
}

func TestNewOrgPolicy_AllowAll(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewOrgPolicy(ctx, "test-allow-all", &OrgPolicyArgs{
			ParentID:   pulumi.String("organizations/222"),
			Constraint: pulumi.String("constraints/compute.trustedImageProjects"),
			AllowAll:   pulumi.Bool(true),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, orgPolicyType, 1)
}

func TestNewOrgPolicy_AllowValues(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewOrgPolicy(ctx, "test-allow-vals", &OrgPolicyArgs{
			ParentID:   pulumi.String("organizations/333"),
			Constraint: pulumi.String("constraints/compute.trustedImageProjects"),
			AllowValues: pulumi.StringArray{
				pulumi.String("projects/my-trusted-images"),
				pulumi.String("projects/cos-cloud"),
			},
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, orgPolicyType, 1)
}

func TestNewOrgPolicy_DenyValues(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewOrgPolicy(ctx, "test-deny-vals", &OrgPolicyArgs{
			ParentID:   pulumi.String("organizations/444"),
			Constraint: pulumi.String("constraints/gcp.resourceLocations"),
			DenyValues: pulumi.StringArray{
				pulumi.String("in:asia-locations"),
			},
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, orgPolicyType, 1)
}

func TestNewOrgPolicy_AllowAndDenyValues(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewOrgPolicy(ctx, "test-both-vals", &OrgPolicyArgs{
			ParentID:   pulumi.String("organizations/555"),
			Constraint: pulumi.String("constraints/gcp.resourceLocations"),
			AllowValues: pulumi.StringArray{
				pulumi.String("in:us-locations"),
			},
			DenyValues: pulumi.StringArray{
				pulumi.String("in:asia-locations"),
			},
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, orgPolicyType, 1)
}

func TestNewOrgPolicy_NoRules(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		p, err := NewOrgPolicy(ctx, "test-no-rules", &OrgPolicyArgs{
			ParentID:   pulumi.String("organizations/666"),
			Constraint: pulumi.String("constraints/something"),
		})
		require.NoError(t, err)
		assert.NotNil(t, p.Policy)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, orgPolicyType, 1)
}

func TestNewOrgPolicy_PolicyNameConstruction(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewOrgPolicy(ctx, "test-name-construction", &OrgPolicyArgs{
			ParentID:   pulumi.String("organizations/999"),
			Constraint: pulumi.String("constraints/compute.disableSerialPortAccess"),
			Boolean:    pulumi.Bool(true),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	policies := tracker.RequireType(t, orgPolicyType, 1)
	assert.Equal(t, "organizations/999/policies/compute.disableSerialPortAccess",
		policies[0].Inputs["name"].StringValue())
}

func TestNewOrgPolicy_FolderParent(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewOrgPolicy(ctx, "test-folder-parent", &OrgPolicyArgs{
			ParentID:   pulumi.String("folders/12345"),
			Constraint: pulumi.String("constraints/compute.skipDefaultNetworkCreation"),
			Boolean:    pulumi.Bool(true),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	policies := tracker.RequireType(t, orgPolicyType, 1)
	assert.Equal(t, "folders/12345", policies[0].Inputs["parent"].StringValue())
	assert.Equal(t, "folders/12345/policies/compute.skipDefaultNetworkCreation",
		policies[0].Inputs["name"].StringValue())
}
