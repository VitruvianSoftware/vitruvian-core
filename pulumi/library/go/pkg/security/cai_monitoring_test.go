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

package security

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// helper runs NewCAIMonitoring inside a mocked Pulumi context and returns
// the resource tracker and any error from the constructor.
func runCAIMonitoring(t *testing.T, args *CAIMonitoringArgs) (*testutil.ResourceTracker, error) {
	t.Helper()
	tracker := testutil.NewTracker()
	var compErr error
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, compErr = NewCAIMonitoring(ctx, "test-cai", args)
		return compErr
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	if err != nil && compErr == nil {
		compErr = err
	}
	return tracker, compErr
}

// base returns a minimal valid CAIMonitoringArgs for testing.
func baseCAIArgs() *CAIMonitoringArgs {
	return &CAIMonitoringArgs{
		OrgID:               pulumi.String("123456"),
		ProjectID:           pulumi.String("my-scc-project"),
		Location:            "us-central1",
		BuildServiceAccount: pulumi.String("projects/my-scc-project/serviceAccounts/builder@my-scc-project.iam.gserviceaccount.com"),
		FunctionSourcePath:  ".", // use current dir as dummy archive source
	}
}

func TestNewCAIMonitoring_NilArgs(t *testing.T) {
	_, err := runCAIMonitoring(t, nil)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "args cannot be nil")
}

func TestNewCAIMonitoring_CreatesAllResources(t *testing.T) {
	tracker, err := runCAIMonitoring(t, baseCAIArgs())
	require.NoError(t, err)

	all := tracker.All()
	// Should create: component + SA + org IAM + 3 project IAM + 3 service identities +
	// AR repo + bucket + bucket object + topic + org feed + SCC source + cloud function = 16+ resources
	assert.GreaterOrEqual(t, len(all), 15, "expected at least 15 resources, got %d", len(all))
}

func TestNewCAIMonitoring_ServiceAccountCreated(t *testing.T) {
	tracker, err := runCAIMonitoring(t, baseCAIArgs())
	require.NoError(t, err)

	sas := tracker.ByType("gcp:serviceaccount/account:Account")
	require.Len(t, sas, 1, "expected exactly 1 service account")
	tracker.AssertInputEquals(t, "test-cai-sa", "accountId", "cai-monitoring")
}

func TestNewCAIMonitoring_OrgIAMFindingsEditor(t *testing.T) {
	tracker, err := runCAIMonitoring(t, baseCAIArgs())
	require.NoError(t, err)

	orgIAMs := tracker.ByType("gcp:organizations/iAMMember:IAMMember")
	require.Len(t, orgIAMs, 1, "expected exactly 1 org IAM member (findings editor)")
	tracker.AssertInputEquals(t, "test-cai-sa-findings-editor", "role", "roles/securitycenter.findingsEditor")
}

func TestNewCAIMonitoring_ProjectIAMRoles(t *testing.T) {
	tracker, err := runCAIMonitoring(t, baseCAIArgs())
	require.NoError(t, err)

	projectIAMs := tracker.ByType("gcp:projects/iAMMember:IAMMember")
	// 3 roles: pubsub.publisher, eventarc.eventReceiver, run.invoker
	assert.Len(t, projectIAMs, 3, "expected 3 project IAM members for CF roles")
}

func TestNewCAIMonitoring_ServiceIdentities(t *testing.T) {
	tracker, err := runCAIMonitoring(t, baseCAIArgs())
	require.NoError(t, err)

	identities := tracker.ByType("gcp:projects/serviceIdentity:ServiceIdentity")
	assert.Len(t, identities, 3, "expected 3 service identities (cloudfunctions, artifactregistry, pubsub)")
}

func TestNewCAIMonitoring_ArtifactRegistry(t *testing.T) {
	tracker, err := runCAIMonitoring(t, baseCAIArgs())
	require.NoError(t, err)

	repos := tracker.ByType("gcp:artifactregistry/repository:Repository")
	require.Len(t, repos, 1)
	tracker.AssertInputEquals(t, "test-cai-ar", "repositoryId", "ar-cai-monitoring")
	tracker.AssertInputEquals(t, "test-cai-ar", "format", "DOCKER")
}

func TestNewCAIMonitoring_StorageBucket(t *testing.T) {
	tracker, err := runCAIMonitoring(t, baseCAIArgs())
	require.NoError(t, err)

	buckets := tracker.ByType("gcp:storage/bucket:Bucket")
	require.Len(t, buckets, 1)
	tracker.AssertInputBool(t, "test-cai-source-bucket", "forceDestroy", true)
	tracker.AssertInputBool(t, "test-cai-source-bucket", "uniformBucketLevelAccess", true)
}

func TestNewCAIMonitoring_SourceArchiveUploaded(t *testing.T) {
	tracker, err := runCAIMonitoring(t, baseCAIArgs())
	require.NoError(t, err)

	objects := tracker.ByType("gcp:storage/bucketObject:BucketObject")
	require.Len(t, objects, 1)
	tracker.AssertInputEquals(t, "test-cai-source-zip", "name", "cai-monitoring-function.zip")
}

func TestNewCAIMonitoring_PubSubTopic(t *testing.T) {
	tracker, err := runCAIMonitoring(t, baseCAIArgs())
	require.NoError(t, err)

	topics := tracker.ByType("gcp:pubsub/topic:Topic")
	require.Len(t, topics, 1)
	tracker.AssertInputEquals(t, "test-cai-topic", "name", "top-cai-monitoring-event")
}

func TestNewCAIMonitoring_OrgFeed(t *testing.T) {
	tracker, err := runCAIMonitoring(t, baseCAIArgs())
	require.NoError(t, err)

	feeds := tracker.ByType("gcp:cloudasset/organizationFeed:OrganizationFeed")
	require.Len(t, feeds, 1)
	tracker.AssertInputEquals(t, "test-cai-org-feed", "feedId", "fd-cai-monitoring")
	tracker.AssertInputEquals(t, "test-cai-org-feed", "contentType", "IAM_POLICY")
}

func TestNewCAIMonitoring_SCCSource(t *testing.T) {
	tracker, err := runCAIMonitoring(t, baseCAIArgs())
	require.NoError(t, err)

	sources := tracker.ByType("gcp:securitycenter/v2OrganizationSource:V2OrganizationSource")
	require.Len(t, sources, 1)
	tracker.AssertInputEquals(t, "test-cai-scc-source", "displayName", "CAI Monitoring")
}

func TestNewCAIMonitoring_CloudFunctionV2(t *testing.T) {
	tracker, err := runCAIMonitoring(t, baseCAIArgs())
	require.NoError(t, err)

	functions := tracker.ByType("gcp:cloudfunctionsv2/function:Function")
	require.Len(t, functions, 1)
	tracker.AssertInputEquals(t, "test-cai-function", "name", "caiMonitoring")
}

func TestNewCAIMonitoring_DefaultRoles(t *testing.T) {
	// Verify that the default roles match the upstream 5-role set
	assert.Len(t, DefaultRolesToMonitor, 5)
	assert.Contains(t, DefaultRolesToMonitor, "roles/owner")
	assert.Contains(t, DefaultRolesToMonitor, "roles/editor")
	assert.Contains(t, DefaultRolesToMonitor, "roles/resourcemanager.organizationAdmin")
	assert.Contains(t, DefaultRolesToMonitor, "roles/compute.networkAdmin")
	assert.Contains(t, DefaultRolesToMonitor, "roles/compute.orgFirewallPolicyAdmin")
}

func TestNewCAIMonitoring_CustomRoles(t *testing.T) {
	args := baseCAIArgs()
	args.RolesToMonitor = []string{"roles/owner", "roles/editor"}

	tracker, err := runCAIMonitoring(t, args)
	require.NoError(t, err)

	// The function should still be created — just with different env vars
	functions := tracker.ByType("gcp:cloudfunctionsv2/function:Function")
	require.Len(t, functions, 1)
}

func TestNewCAIMonitoring_DefaultLocation(t *testing.T) {
	args := baseCAIArgs()
	args.Location = "" // should default to us-central1

	tracker, err := runCAIMonitoring(t, args)
	require.NoError(t, err)

	tracker.AssertInputEquals(t, "test-cai-ar", "location", "us-central1")
}

func TestNewCAIMonitoring_CustomLocation(t *testing.T) {
	args := baseCAIArgs()
	args.Location = "europe-west1"

	tracker, err := runCAIMonitoring(t, args)
	require.NoError(t, err)

	tracker.AssertInputEquals(t, "test-cai-ar", "location", "europe-west1")
}

func TestNewCAIMonitoring_CMEKEncryptionKey(t *testing.T) {
	args := baseCAIArgs()
	args.EncryptionKey = "projects/my-proj/locations/us/keyRings/kr/cryptoKeys/key"

	tracker, err := runCAIMonitoring(t, args)
	require.NoError(t, err)

	repos := tracker.ByType("gcp:artifactregistry/repository:Repository")
	require.Len(t, repos, 1)
	// Verify the KMS key was set
	kmsVal := repos[0].Inputs["kmsKeyName"]
	assert.False(t, kmsVal.IsNull(), "kmsKeyName should be set when EncryptionKey is provided")
}

func TestNewCAIMonitoring_NoCMEKByDefault(t *testing.T) {
	tracker, err := runCAIMonitoring(t, baseCAIArgs())
	require.NoError(t, err)

	repos := tracker.ByType("gcp:artifactregistry/repository:Repository")
	require.Len(t, repos, 1)
	// Verify the KMS key was NOT set
	kmsVal := repos[0].Inputs["kmsKeyName"]
	assert.True(t, kmsVal.IsNull(), "kmsKeyName should be null when EncryptionKey is empty")
}
