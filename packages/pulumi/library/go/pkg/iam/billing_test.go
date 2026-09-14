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

func TestNewBillingIAMMember(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewBillingIAMMember(ctx, "test-bill-iam", &BillingIAMMemberArgs{
			BillingAccountID: pulumi.String("AAAAAA-BBBBBB-CCCCCC"),
			Role:             pulumi.String("roles/billing.user"),
			Member:           pulumi.String("serviceAccount:tf@p.iam.gserviceaccount.com"),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	members := tracker.RequireType(t, "gcp:billing/accountIamMember:AccountIamMember", 1)
	assert.Equal(t, "AAAAAA-BBBBBB-CCCCCC", members[0].Inputs["billingAccountId"].StringValue())
}

func TestNewBillingIAMBinding(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewBillingIAMBinding(ctx, "test-bill-binding", &BillingIAMBindingArgs{
			BillingAccountID: pulumi.String("AAAAAA-BBBBBB-CCCCCC"),
			Role:             pulumi.String("roles/billing.viewer"),
			Members:          pulumi.StringArray{pulumi.String("user:fin@example.com")},
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:billing/accountIamBinding:AccountIamBinding", 1)
}

func TestNewBillingIAMMember_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewBillingIAMMember(ctx, "test", nil)
		return err
	}, pulumi.WithMocks("test", "test", testutil.NewTracker()))
	require.ErrorContains(t, err, "args cannot be nil")
}

func TestNewBillingIAMBinding_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewBillingIAMBinding(ctx, "test", nil)
		return err
	}, pulumi.WithMocks("test", "test", testutil.NewTracker()))
	require.ErrorContains(t, err, "args cannot be nil")
}

func TestNewBillingIAMMember_EmptyName(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewBillingIAMMember(ctx, "", &BillingIAMMemberArgs{})
		return err
	}, pulumi.WithMocks("test", "test", testutil.NewTracker()))
	require.Error(t, err)
}

func TestNewBillingIAMBinding_EmptyName(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewBillingIAMBinding(ctx, "", &BillingIAMBindingArgs{})
		return err
	}, pulumi.WithMocks("test", "test", testutil.NewTracker()))
	require.Error(t, err)
}
