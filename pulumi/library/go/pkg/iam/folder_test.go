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

func TestNewFolderIAMMember(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewFolderIAMMember(ctx, "test-folder-iam", &FolderIAMMemberArgs{
			FolderID: pulumi.String("folders/789"),
			Role:     pulumi.String("roles/editor"),
			Member:   pulumi.String("serviceAccount:sa@p.iam.gserviceaccount.com"),
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	members := tracker.RequireType(t, "gcp:folder/iAMMember:IAMMember", 1)
	assert.Equal(t, "folders/789", members[0].Inputs["folder"].StringValue())
}

func TestNewFolderIAMBinding(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewFolderIAMBinding(ctx, "test-folder-binding", &FolderIAMBindingArgs{
			FolderID: pulumi.String("folders/999"),
			Role:     pulumi.String("roles/editor"),
			Members:  pulumi.StringArray{pulumi.String("user:c@example.com")},
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:folder/iAMBinding:IAMBinding", 1)
}

func TestNewFolderIAMMember_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewFolderIAMMember(ctx, "test", nil)
		return err
	}, pulumi.WithMocks("test", "test", testutil.NewTracker()))
	require.ErrorContains(t, err, "args cannot be nil")
}

func TestNewFolderIAMBinding_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewFolderIAMBinding(ctx, "test", nil)
		return err
	}, pulumi.WithMocks("test", "test", testutil.NewTracker()))
	require.ErrorContains(t, err, "args cannot be nil")
}

func TestNewFolderIAMMember_EmptyName(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewFolderIAMMember(ctx, "", &FolderIAMMemberArgs{})
		return err
	}, pulumi.WithMocks("test", "test", testutil.NewTracker()))
	require.Error(t, err)
}

func TestNewFolderIAMBinding_EmptyName(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewFolderIAMBinding(ctx, "", &FolderIAMBindingArgs{})
		return err
	}, pulumi.WithMocks("test", "test", testutil.NewTracker()))
	require.Error(t, err)
}
