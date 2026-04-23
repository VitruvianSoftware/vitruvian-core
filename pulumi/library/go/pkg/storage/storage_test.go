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

package storage

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/storage"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	gcpBucket = "gcp:storage/bucket:Bucket"
)

func basicBucketArgs() *SimpleBucketArgs {
	return &SimpleBucketArgs{
		Name:         pulumi.String("test-bucket-name"),
		ProjectID:    pulumi.String("prj-test-123"),
		Location:     pulumi.String("us-central1"),
		ForceDestroy: pulumi.Bool(false),
	}
}

// ---------- Nil Guard ----------

func TestNewSimpleBucket_NilArgs(t *testing.T) {
	_, err := NewSimpleBucket(nil, "test", nil)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "args cannot be nil")
}

// ---------- Basic Creation ----------

func TestNewSimpleBucket_CreatesBucket(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		sb, err := NewSimpleBucket(ctx, "test-sb", basicBucketArgs())
		require.NoError(t, err)
		assert.NotNil(t, sb.Bucket)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, gcpBucket, 1)
}

// ---------- Defaults ----------

func TestNewSimpleBucket_UniformBucketLevelAccess(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewSimpleBucket(ctx, "test-ubla", basicBucketArgs())
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	buckets := tracker.RequireType(t, gcpBucket, 1)
	assert.True(t, buckets[0].Inputs["uniformBucketLevelAccess"].BoolValue(),
		"uniform bucket-level access should be enabled by default")
}

func TestNewSimpleBucket_PublicAccessPrevention(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewSimpleBucket(ctx, "test-pap", basicBucketArgs())
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	buckets := tracker.RequireType(t, gcpBucket, 1)
	assert.Equal(t, "enforced", buckets[0].Inputs["publicAccessPrevention"].StringValue(),
		"public access prevention should be enforced by default")
}

// ---------- Location ----------

func TestNewSimpleBucket_LocationPropagated(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicBucketArgs()
		args.Location = pulumi.String("europe-west1")
		_, err := NewSimpleBucket(ctx, "test-loc", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	buckets := tracker.RequireType(t, gcpBucket, 1)
	assert.Equal(t, "europe-west1", buckets[0].Inputs["location"].StringValue())
}

// ---------- Encryption ----------

func TestNewSimpleBucket_WithEncryption(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicBucketArgs()
		args.Encryption = &storage.BucketEncryptionArgs{
			DefaultKmsKeyName: pulumi.String("projects/prj/locations/us/keyRings/kr/cryptoKeys/key"),
		}
		_, err := NewSimpleBucket(ctx, "test-enc", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	buckets := tracker.RequireType(t, gcpBucket, 1)
	enc := buckets[0].Inputs["encryption"]
	require.True(t, enc.IsObject(), "encryption should be set")
}

func TestNewSimpleBucket_WithoutEncryption(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewSimpleBucket(ctx, "test-no-enc", basicBucketArgs())
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	buckets := tracker.RequireType(t, gcpBucket, 1)
	enc := buckets[0].Inputs["encryption"]
	assert.True(t, enc.IsNull(), "encryption should not be set when not provided")
}

// ---------- Versioning ----------

func TestNewSimpleBucket_VersioningEnabled(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicBucketArgs()
		enabled := true
		args.Versioning = &enabled
		_, err := NewSimpleBucket(ctx, "test-ver", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	buckets := tracker.RequireType(t, gcpBucket, 1)
	ver := buckets[0].Inputs["versioning"]
	require.True(t, ver.IsObject(), "versioning should be set")
}

func TestNewSimpleBucket_VersioningDefault(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewSimpleBucket(ctx, "test-no-ver", basicBucketArgs())
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	buckets := tracker.RequireType(t, gcpBucket, 1)
	ver := buckets[0].Inputs["versioning"]
	assert.True(t, ver.IsNull(), "versioning should not be set by default")
}

// ---------- Force Destroy ----------

func TestNewSimpleBucket_ForceDestroyPropagated(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicBucketArgs()
		args.ForceDestroy = pulumi.Bool(true)
		_, err := NewSimpleBucket(ctx, "test-fd", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	buckets := tracker.RequireType(t, gcpBucket, 1)
	assert.True(t, buckets[0].Inputs["forceDestroy"].BoolValue())
}

// ---------- Labels ----------

func TestNewSimpleBucket_LabelsPropagated(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicBucketArgs()
		args.Labels = pulumi.StringMap{
			"environment": pulumi.String("bootstrap"),
			"team":        pulumi.String("platform"),
		}
		_, err := NewSimpleBucket(ctx, "test-labels", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	buckets := tracker.RequireType(t, gcpBucket, 1)
	labels := buckets[0].Inputs["labels"]
	require.True(t, labels.IsObject(), "labels should be set")
	assert.Equal(t, "bootstrap", labels.ObjectValue()["environment"].StringValue())
	assert.Equal(t, "platform", labels.ObjectValue()["team"].StringValue())
}
