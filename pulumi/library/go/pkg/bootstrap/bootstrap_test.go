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

package bootstrap

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	gcpProject   = "gcp:organizations/project:Project"
	gcpService   = "gcp:projects/service:Service"
	gcpKeyRing   = "gcp:kms/keyRing:KeyRing"
	gcpCryptoKey = "gcp:kms/cryptoKey:CryptoKey"
	gcpBucket    = "gcp:storage/bucket:Bucket"
	gcpOrgPolicy = "gcp:projects/organizationPolicy:OrganizationPolicy"
	gcpLien      = "gcp:resourcemanager/lien:Lien"
	gcpDefaultSA = "gcp:projects/defaultServiceAccounts:DefaultServiceAccounts"
	gcpBucketIAM = "gcp:storage/bucketIAMMember:BucketIAMMember"
	randomID     = "random:index/randomId:RandomId"
)

func basicArgs() *BootstrapArgs {
	return &BootstrapArgs{
		OrgID:          "123456789",
		FolderID:       pulumi.String("folders/111"),
		BillingAccount: "AAAAAA-BBBBBB-CCCCCC",
		ProjectPrefix:  "prj",
		DefaultRegion:  "us-central1",
		ProjectLabels: pulumi.StringMap{
			"environment": pulumi.String("bootstrap"),
		},
		ActivateApis: []string{"compute.googleapis.com", "iam.googleapis.com"},
	}
}

// ---------- Basic Creation ----------

func TestNewBootstrap_CreatesAllResources(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		b, err := NewBootstrap(ctx, "test-boot", basicArgs())
		require.NoError(t, err)
		assert.NotNil(t, b.SeedProject)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	// Should create: project, lien, default SA, KMS keyring, crypto key,
	// bucket, org policy, + API services
	tracker.RequireType(t, gcpProject, 1)
	tracker.RequireType(t, gcpKeyRing, 1)
	tracker.RequireType(t, gcpCryptoKey, 1)
	tracker.RequireType(t, gcpBucket, 1)
	tracker.RequireType(t, gcpOrgPolicy, 1)
	tracker.RequireType(t, gcpLien, 1)
	tracker.RequireType(t, gcpDefaultSA, 1)
}

func TestNewBootstrap_SeedProjectHasLien(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewBootstrap(ctx, "test-lien", basicArgs())
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	liens := tracker.RequireType(t, gcpLien, 1)
	assert.Equal(t, "project-factory", liens[0].Inputs["origin"].StringValue())
}

func TestNewBootstrap_DefaultSADisabled(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewBootstrap(ctx, "test-dsa", basicArgs())
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	dsas := tracker.RequireType(t, gcpDefaultSA, 1)
	assert.Equal(t, "DISABLE", dsas[0].Inputs["action"].StringValue())
}

// ---------- Org Policy ----------

func TestNewBootstrap_CrossProjectSAPolicy(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewBootstrap(ctx, "test-policy", basicArgs())
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	policies := tracker.RequireType(t, gcpOrgPolicy, 1)
	assert.Equal(t, "iam.disableCrossProjectServiceAccountUsage",
		policies[0].Inputs["constraint"].StringValue())
}

// ---------- KMS ----------

func TestNewBootstrap_KMSCreated(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewBootstrap(ctx, "test-kms", basicArgs())
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	keyRings := tracker.RequireType(t, gcpKeyRing, 1)
	assert.Equal(t, "prj-keyring", keyRings[0].Inputs["name"].StringValue())

	keys := tracker.RequireType(t, gcpCryptoKey, 1)
	assert.Equal(t, "prj-key", keys[0].Inputs["name"].StringValue())
	assert.Equal(t, "7776000s", keys[0].Inputs["rotationPeriod"].StringValue())
}

func TestNewBootstrap_NoKMSWhenEncryptionDisabled(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicArgs()
		noEncrypt := false
		args.EncryptStateBucket = &noEncrypt
		_, err := NewBootstrap(ctx, "test-no-kms", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	assert.Equal(t, 0, tracker.TypeCount(gcpKeyRing))
	assert.Equal(t, 0, tracker.TypeCount(gcpCryptoKey))
	tracker.RequireType(t, gcpBucket, 1) // bucket still created
}

// ---------- State Bucket ----------

func TestNewBootstrap_StateBucketCreated(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewBootstrap(ctx, "test-bucket", basicArgs())
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	buckets := tracker.RequireType(t, gcpBucket, 1)
	assert.Equal(t, "us-central1", buckets[0].Inputs["location"].StringValue())
	assert.True(t, buckets[0].Inputs["uniformBucketLevelAccess"].BoolValue())
}

// ---------- Bucket IAM ----------

func TestNewBootstrap_BucketIAMMembers(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicArgs()
		args.StateBucketIAMMembers = []pulumi.StringInput{
			pulumi.String("serviceAccount:sa@project.iam.gserviceaccount.com"),
			pulumi.String("group:admins@example.com"),
		}
		_, err := NewBootstrap(ctx, "test-iam", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	iamMembers := tracker.RequireType(t, gcpBucketIAM, 2)
	roles := map[string]bool{}
	for _, m := range iamMembers {
		roles[m.Inputs["role"].StringValue()] = true
	}
	assert.True(t, roles["roles/storage.admin"])
}

// ---------- Random Suffix ----------

func TestNewBootstrap_RandomSuffix(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicArgs()
		args.RandomSuffix = true
		_, err := NewBootstrap(ctx, "test-random", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	// Should have 2 random IDs: one for project suffix, one for bucket suffix
	randomIDs := tracker.RequireType(t, randomID, 2)
	names := map[string]bool{}
	for _, r := range randomIDs {
		names[r.Name] = true
	}
	assert.True(t, names["test-random-seed-suffix"], "should have project suffix")
	assert.True(t, names["test-random-bucket-suffix"], "should have bucket suffix")
}

// ---------- KMS cloudkms API Auto-Addition ----------

func TestNewBootstrap_CloudKMSAPIAutoAdded(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicArgs()
		// APIs don't include cloudkms, but encryption is on by default
		args.ActivateApis = []string{"compute.googleapis.com"}
		_, err := NewBootstrap(ctx, "test-kms-api", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	services := tracker.RequireType(t, gcpService, 2) // compute + cloudkms
	apis := map[string]bool{}
	for _, svc := range services {
		apis[svc.Inputs["service"].StringValue()] = true
	}
	assert.True(t, apis["cloudkms.googleapis.com"],
		"cloudkms should be auto-added when encryption is enabled")
}

func TestAppendIfMissing(t *testing.T) {
	orig := []string{"foo", "bar"}
	res1 := appendIfMissing(orig, "foo")
	assert.Equal(t, orig, res1)
	res2 := appendIfMissing(orig, "baz")
	assert.Equal(t, []string{"foo", "bar", "baz"}, res2)
}
