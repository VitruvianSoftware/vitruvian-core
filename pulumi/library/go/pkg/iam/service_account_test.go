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
	"github.com/stretchr/testify/require"
)

func TestNewServiceAccountIAMMember(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewServiceAccountIAMMember(ctx, "test-sa-iam", &ServiceAccountIAMMemberArgs{
			ServiceAccountID: pulumi.String("projects/p/serviceAccounts/sa@p.iam.gserviceaccount.com"),
			Role:             pulumi.String("roles/iam.serviceAccountTokenCreator"),
			Member:           pulumi.String("user:dev@example.com"),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:serviceaccount/iAMMember:IAMMember", 1)
}

func TestNewServiceAccountIAMBinding(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewServiceAccountIAMBinding(ctx, "test-sa-binding", &ServiceAccountIAMBindingArgs{
			ServiceAccountID: pulumi.String("projects/p/serviceAccounts/sa@p.iam.gserviceaccount.com"),
			Role:             pulumi.String("roles/iam.serviceAccountUser"),
			Members:          pulumi.StringArray{pulumi.String("user:dev@example.com")},
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:serviceaccount/iAMBinding:IAMBinding", 1)
}

func TestNewServiceAccountIAMMember_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewServiceAccountIAMMember(ctx, "test", nil)
		return err
	}, pulumi.WithMocks("test", "test", testutil.NewTracker()))
	require.ErrorContains(t, err, "args cannot be nil")
}

func TestNewServiceAccountIAMBinding_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewServiceAccountIAMBinding(ctx, "test", nil)
		return err
	}, pulumi.WithMocks("test", "test", testutil.NewTracker()))
	require.ErrorContains(t, err, "args cannot be nil")
}

func TestNewServiceAccountIAMMember_EmptyName(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewServiceAccountIAMMember(ctx, "", &ServiceAccountIAMMemberArgs{})
		return err
	}, pulumi.WithMocks("test", "test", testutil.NewTracker()))
	require.Error(t, err)
}

func TestNewServiceAccountIAMBinding_EmptyName(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewServiceAccountIAMBinding(ctx, "", &ServiceAccountIAMBindingArgs{})
		return err
	}, pulumi.WithMocks("test", "test", testutil.NewTracker()))
	require.Error(t, err)
}
