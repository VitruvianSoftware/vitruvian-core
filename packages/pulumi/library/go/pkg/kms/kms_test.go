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

package kms

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/require"
)

func TestNewKms_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewKms(ctx, "test", nil)
		require.Error(t, err)
		require.Contains(t, err.Error(), "args is required")
		return nil
	}, pulumi.WithMocks("project", "stack", testutil.NewTracker()))
	require.NoError(t, err)
}

func TestNewKms_BasicKeyring(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		result, err := NewKms(ctx, "test-kms", &KmsArgs{
			ProjectID:   pulumi.String("test-proj"),
			Location:    "us-central1",
			KeyringName: "test-keyring",
		})
		require.NoError(t, err)
		require.NotNil(t, result.Keyring)
		require.Len(t, result.Keys, 0)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:kms/keyRing:KeyRing", 1)
	tracker.RequireType(t, "gcp:kms/cryptoKey:CryptoKey", 0)
}

func TestNewKms_WithKeys(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		result, err := NewKms(ctx, "test-kms-keys", &KmsArgs{
			ProjectID:   pulumi.String("test-proj"),
			Location:    "us-central1",
			KeyringName: "app-keyring",
			Keys: []KeyConfig{
				{Name: "data-key", RotationPeriod: "7776000s"},
				{Name: "config-key", Purpose: "ENCRYPT_DECRYPT"},
			},
		})
		require.NoError(t, err)
		require.Len(t, result.Keys, 2)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:kms/keyRing:KeyRing", 1)
	tracker.RequireType(t, "gcp:kms/cryptoKey:CryptoKey", 2)
}
